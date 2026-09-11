import json

from pipeline_core import validators


QUERIES = ["CRDT overview survey", "systematic review collaborative editing",
           "meta-analysis replicated data consistency", "operational transformation comparison",
           "eventual consistency empirical evaluation", "CRDT limitations failure cases"]

GOOD_PLAN = json.dumps({
    "strategy": "Survey the field, then drill into empirical evaluations.",
    "queries": QUERIES,
    "disconfirming_query": "CRDT limitations failure cases",
    "outline": "## Background\n## Methods\n## Findings",
})


def reader_doc(n=5, drop_authors_in=None, depth="abstract", sources=None):
    parts = ["# Source Notes\n"]
    for i in range(1, n + 1):
        src = sources[i - 1] if sources else i
        parts.append(f"## Paper {i}: Title {i}")
        if i != drop_authors_in:
            parts.append("**Authors:** Smith, Jones")
        parts.append(f"**Year:** 2021\n**Source:** #{src}\n**Read depth:** {depth}\n")
        parts.append("### Research Question\n" + "x" * 100 + "\n")
        if depth != "metadata-only":
            parts.append("### Findings\n- 42% of cases converge.\n")
    return "\n".join(parts)


SIGNAL_DOC = "\n".join([
    "# Research Gap Analysis & Opportunities",
    "## Executive Summary\ntext",
    "## 1. Major Research Gaps\ntext",
    "## 2. Emerging Trends (2023-2024)\ntext",
    "## 3. Unresolved Questions & Contradictions\ntext",
    "## 8. Your Novel Research Angles\ntext",
    "## 10. Next Steps Recommendations\ntext",
])

PAPERS = [{"authors": ["Smith", "Jones"], "year": 2021},
          {"authors": ["Kleppmann", "Wiggins"], "year": 2019}]

REVIEW_DOC = "\n".join([
    "# Literature Review: CRDTs",
    "## Scope and method\nSearched three APIs.",
    "## Convergence\nMerges converge (Smith et al., 2021; Kleppmann & Wiggins, 2019).",
    "## Cross-source synthesis\nThis contradicts (Kleppmann, 2019).",
    "## Coverage limits\nNo clinical sources.",
])


class TestPlan:
    def test_good(self):
        assert validators.validate_plan(GOOD_PLAN) == []

    def test_fenced_json_ok(self):
        assert validators.validate_plan(f"```json\n{GOOD_PLAN}\n```") == []

    def test_not_json(self):
        errs = validators.validate_plan("here is my plan: search stuff")
        assert errs and "valid JSON" in errs[0]

    def test_missing_key(self):
        errs = validators.validate_plan(json.dumps({"queries": ["a b c"]}))
        assert any("outline" in e for e in errs) and any("strategy" in e for e in errs)

    def test_too_few_queries(self):
        bad = json.loads(GOOD_PLAN); bad["queries"] = QUERIES[:5]
        bad["disconfirming_query"] = QUERIES[0]
        assert any("at least 6" in e for e in validators.validate_plan(json.dumps(bad)))

    def test_duplicate_queries(self):
        bad = json.loads(GOOD_PLAN); bad["queries"] = QUERIES[:5] + ["crdt OVERVIEW survey"]
        assert any("duplicate" in e for e in validators.validate_plan(json.dumps(bad)))

    def test_disconfirming_query_required(self):
        bad = json.loads(GOOD_PLAN); del bad["disconfirming_query"]
        assert any("disconfirming_query" in e for e in validators.validate_plan(json.dumps(bad)))

    def test_disconfirming_query_must_be_one_of_the_queries(self):
        bad = json.loads(GOOD_PLAN); bad["disconfirming_query"] = "something not searched"
        errs = validators.validate_plan(json.dumps(bad))
        assert any("disconfirming_query" in e and "queries" in e for e in errs)


class TestReader:
    def test_good(self):
        assert validators.validate_reader(reader_doc(5), pool_size=10, min_sections=5) == []

    def test_no_sections(self):
        errs = validators.validate_reader("just prose", pool_size=3, min_sections=3)
        assert "## Paper N: Title" in errs[0]

    def test_missing_authors_names_section(self):
        errs = validators.validate_reader(reader_doc(5, drop_authors_in=3), pool_size=10,
                                          min_sections=5)
        assert any("Paper 3" in e and "Authors" in e for e in errs)

    def test_non_contiguous_numbering(self):
        doc = reader_doc(3).replace("## Paper 2:", "## Paper 7:")
        assert any("contiguous" in e
                   for e in validators.validate_reader(doc, pool_size=10, min_sections=3))

    def test_too_few_sections(self):
        assert any("at least 5" in e
                   for e in validators.validate_reader(reader_doc(2), pool_size=10, min_sections=5))

    def test_source_index_must_resolve_to_a_harvest_row(self):
        doc = reader_doc(2, sources=[1, 11])
        errs = validators.validate_reader(doc, pool_size=10, min_sections=2)
        assert any("#11" in e and "harvest" in e for e in errs)

    def test_source_index_must_be_unique(self):
        doc = reader_doc(2, sources=[4, 4])
        errs = validators.validate_reader(doc, pool_size=10, min_sections=2)
        assert any("#4" in e and "more than once" in e for e in errs)

    def test_read_depth_tag_required(self):
        doc = reader_doc(2).replace("**Read depth:** abstract", "**Read depth:** skimmed", 1)
        errs = validators.validate_reader(doc, pool_size=10, min_sections=2)
        assert any("Read depth" in e and "Paper 1" in e for e in errs)

    def test_metadata_only_source_may_not_report_findings(self):
        doc = reader_doc(1, depth="metadata-only") + "\n### Findings\n- 90% faster.\n"
        errs = validators.validate_reader(doc, pool_size=10, min_sections=1)
        assert any("metadata-only" in e and "Findings" in e for e in errs)


class TestReview:
    def test_good(self):
        assert validators.validate_review(REVIEW_DOC, papers=PAPERS) == []

    def test_citation_not_in_read_sources_rejected(self):
        doc = REVIEW_DOC + "\nAlso (Doe, 2020) found otherwise."
        errs = validators.validate_review(doc, papers=PAPERS)
        assert any("(Doe, 2020)" in e for e in errs)

    def test_year_must_match(self):
        doc = REVIEW_DOC.replace("(Kleppmann, 2019)", "(Kleppmann, 2018)")
        assert any("Kleppmann, 2018" in e for e in validators.validate_review(doc, papers=PAPERS))

    def test_required_sections(self):
        doc = REVIEW_DOC.replace("## Coverage limits", "## Wrap-up")
        assert any("Coverage limits" in e for e in validators.validate_review(doc, papers=PAPERS))

    def test_must_cite_something(self):
        doc = "## Cross-source synthesis\nprose\n## Coverage limits\nnone"
        assert any("cite" in e for e in validators.validate_review(doc, papers=PAPERS))


class TestSignal:
    def test_good(self):
        assert validators.validate_signal(SIGNAL_DOC) == []

    def test_missing_header(self):
        doc = SIGNAL_DOC.replace("## Executive Summary\ntext", "")
        assert any("Executive Summary" in e for e in validators.validate_signal(doc))

    def test_duplicate_header(self):
        doc = SIGNAL_DOC + "\n## Executive Summary\nagain"
        assert any("exactly once" in e for e in validators.validate_signal(doc))

    def test_headers_must_be_in_order(self):
        doc = SIGNAL_DOC.replace("## 1. Major Research Gaps\ntext\n", "") + \
            "\n## Major Research Gaps\ntext"
        assert any("order" in e for e in validators.validate_signal(doc))


class TestScout:
    GOOD = "\n".join([
        "## Query: CRDT adoption industry",
        "- CRDTs at Figma | Figma Blog | 2023 | https://figma.com/blog/crdts",
        "- Yjs in production | Tag1 | 2022 | https://tag1.com/yjs",
        "- Automerge 2.0 | Ink & Switch | 2023 | https://inkandswitch.com/automerge",
        "## Coverage",
        "All queries sourced.",
    ])

    def test_good(self):
        assert validators.validate_scout(self.GOOD, expected_queries=["CRDT adoption industry"]) == []

    def test_missing_query_section(self):
        errs = validators.validate_scout(self.GOOD, expected_queries=["a", "b"])
        assert any("per requested query" in e for e in errs)

    def test_doi_smuggling_rejected(self):
        doc = self.GOOD + "\n- Fake paper | X | 2020 | https://doi.org/10.1145/12345"
        assert any("DOI" in e for e in validators.validate_scout(doc, expected_queries=["a"]))

    def test_too_few_urls(self):
        doc = "## Query: a\n- only one | pub | 2023 | https://x.com/1\n## Coverage\nok"
        assert any("3 source URLs" in e
                   for e in validators.validate_scout(doc, expected_queries=["a"]))

    def test_coverage_section_required(self):
        doc = self.GOOD.replace("## Coverage\nAll queries sourced.", "")
        assert any("Coverage" in e
                   for e in validators.validate_scout(doc, expected_queries=["CRDT adoption industry"]))
