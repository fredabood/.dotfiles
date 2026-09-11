# Contracts the pipeline enforces

Every worker output is checked by `scripts/pipeline_core/validators.py` before the run
advances. A rejection returns these errors verbatim; they are the correction brief. Three
attempts per step (two for the scout), then the step degrades or the run fails — see SKILL.md.

This file mirrors the code. If they ever disagree, the code is what runs.

## `s0_plan` — planner → `plan.json`

- a single JSON object (markdown fences tolerated) with `strategy`, `queries`, `outline`
- 6–12 non-empty queries, each ≤12 words, no case-insensitive duplicates
- `disconfirming_query` present and copied exactly from `queries`

## `s1_harvest` — deterministic

- per API, every usable record among its top 5; the chain is walked until 5 records per query
- dedup on `(first author, year, title)`, lowercased
- clients drop records with no author, no year, no title, a future or pre-1900 year, or an
  institutional / URL-shaped author
- every query runs; the pool is then filled round-robin in plan order (each query's best
  record, then each query's second, …) up to `max(2 × target, 20)`, so no query — least of all
  the disconfirming one — is starved by network timing
- tier against target: `EXCELLENT` ≥100% · `ACCEPTABLE` ≥86% · `MINIMAL` ≥70% · `FAILED`
- `--web-scout auto` scouts when the tier is `FAILED`, or when some queries returned nothing
  and the tier is below `EXCELLENT`

## `s2_scout` — web-scout → `scout_findings.md`

- one `## Query: <text>` section per requested query
- bullets of the form `- <title> | <publisher> | <year> | <url>`
- at least 3 URLs overall
- **no DOIs anywhere**
- a `## Coverage` section

After merge (`s3_merge`) the tier is recomputed; still `FAILED` fails the run.

## `s4_read` — reader → `reader_output.md`

Per section, numbered `## Paper 1: …` contiguously:

- `**Authors:**`, `**Year:** YYYY`, `**Source:** #N`, `**Read depth:**` lines
- `#N` is a real harvest row and appears in only one section
- read depth is one of `full-text`, `abstract`, `metadata-only`
- a `metadata-only` section has **no Findings heading**
- at least 5 sections (or every row, if fewer were harvested)

The split step (`s5_split`) writes one file per section to `papers/` and records each source's
read depth; the bibliography covers exactly these sources.

## `s6_review` — review-writer → `review.md`

- `## Cross-source synthesis` and `## Coverage limits` headings
- at least one inline citation
- every citation — `(Surname, Year)`, `(Surname et al., Year)`, `(A & B, Year)`, several joined
  by `;`, or narrative `Surname (Year)` — matches the author and year of a source with notes

## `s7_signal` — signal → `signal_output.md`

- headings containing, in this order and each exactly once: Executive Summary, Major Research
  Gaps, Emerging Trends, Unresolved Questions, Novel Research Angles, Next Steps

## `s8_biblio` — deterministic

- `bibliography.json`: dense ids `cite_001…cite_NNN` assigned after dedup; every entry carries
  `read_depth`
- `bibliography.md`: APA-style entries grouped into **Peer-reviewed sources**, **Preprints**
  (arXiv / bioRxiv / medRxiv / SSRN / Research Square, tagged `[PREPRINT]`), and **Web and
  industry sources** (no DOIs)

`source_type` in the JSON is one of `journal`, `book`, `conference`, `report`, `website`
(plus the vendored legal types). BibTeX or CSL-JSON are mechanical conversions of the JSON.

## What the validators cannot check

They check shape and provenance, not truth. Nothing mechanical confirms that a finding in the
notes is what the fetched text says, or that a review claim is fair to its source. That is
what the read-depth tags make auditable and what the eval in `evals/` scores. When unsure
whether a claim is supported, weaken the claim — never strengthen the citation.
