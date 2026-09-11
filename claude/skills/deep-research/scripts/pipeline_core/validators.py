"""Submission validators. Each returns a list of error strings — empty means
accepted. Errors are fed back to the worker verbatim as the correction brief,
so word them as actionable instructions.
"""

from __future__ import annotations

import json
import re

from pydantic import ValidationError

from .vendor.models import ResearchPlan, strip_markdown_json

# Sections the splitter depends on (upstream regex, frozen from the 1.7.4 wheel).
SCRIBE_SECTION_RE = re.compile(r"^##\s*(?:Paper\s*)?(\d+)[:.]\s*(.+?)\s*$", re.MULTILINE)
AUTHORS_RE = re.compile(r"\*\*Authors?:\*\*\s*(\S[^\n]*)")
YEAR_RE = re.compile(r"\*\*Year:\*\*\s*(\d{4})")
SOURCE_RE = re.compile(r"\*\*Source:\*\*\s*#?(\d+)")
READ_DEPTH_RE = re.compile(r"\*\*Read depth:\*\*\s*([\w-]+)")
FINDINGS_HEADING_RE = re.compile(r"^#{2,4}\s*(?:Key\s+)?Findings\b", re.MULTILINE | re.IGNORECASE)

READ_DEPTHS = ("full-text", "abstract", "metadata-only")

# The gap-analysis headings, in order, each exactly once. Loose-matched against
# heading lines: models renumber and decorate, but these anchors must exist.
SIGNAL_REQUIRED_SECTIONS = (
    "Executive Summary",
    "Major Research Gaps",
    "Emerging Trends",
    "Unresolved Questions",
    "Novel Research Angles",
    "Next Steps",
)

REVIEW_REQUIRED_SECTIONS = ("Cross-source synthesis", "Coverage limits")

URL_RE = re.compile(r"https?://\S+")
SCOUT_QUERY_HEADER_RE = re.compile(r"^##\s*Query:\s*(.+?)\s*$", re.MULTILINE)
SCOUT_COVERAGE_RE = re.compile(r"^##\s*Coverage\b", re.MULTILINE | re.IGNORECASE)

# One parenthetical may hold several citations separated by ';'.
_PAREN_RE = re.compile(r"\(([^()]*\b\d{4}[a-z]?[^()]*)\)")
_CITE_RE = re.compile(
    r"^\s*(?:see\s+|e\.g\.,?\s+|cf\.\s+)?"
    r"(?P<surname>[A-Z][\w'’\-]+(?:\s+(?:de|van|von|der|da|di|la|le)\s+[A-Z][\w'’\-]+)?)"
    r"(?:\s+et\s+al\.?|\s+(?:and|&)\s+[A-Z][\w'’\-]+)?"
    r",?\s+(?P<year>\d{4})[a-z]?\s*$"
)


def _heading_lines(content: str) -> list[str]:
    return [ln.lstrip("#").strip().lower() for ln in content.splitlines() if ln.startswith("#")]


def validate_plan(content: str, *, min_queries: int = 6, max_queries: int = 12) -> list[str]:
    errors: list[str] = []
    try:
        data = json.loads(strip_markdown_json(content))
    except ValueError as exc:
        return [f"Output must be a single valid JSON object (parse error: {exc}). "
                "Return ONLY the JSON — no prose, no markdown fences."]
    try:
        plan = ResearchPlan.model_validate(data)
    except ValidationError as exc:
        return [f"JSON does not match the ResearchPlan schema: {e['loc']}: {e['msg']}"
                for e in exc.errors()]

    queries = [q.strip() for q in plan.queries if q.strip()]
    if len(queries) < min_queries:
        errors.append(f"queries: need at least {min_queries} non-empty search queries "
                      f"(got {len(queries)}).")
    if len(queries) > max_queries:
        errors.append(f"queries: at most {max_queries} queries (got {len(queries)}) — "
                      "keep the strongest ones.")
    if len({q.lower() for q in queries}) != len(queries):
        errors.append("queries: remove duplicate queries (case-insensitive).")
    long = [q for q in queries if len(q.split()) > 12]
    if long:
        errors.append(f"queries: keep queries short keyword phrases (≤12 words); "
                      f"too long: {long[:3]}")

    disconfirming = str(data.get("disconfirming_query") or "").strip()
    if not disconfirming:
        errors.append("disconfirming_query: add a string naming the query aimed at evidence "
                      "AGAINST the expected answer.")
    elif disconfirming.lower() not in {q.lower() for q in queries}:
        errors.append("disconfirming_query: must be one of the queries in 'queries' "
                      "(copy it exactly).")
    return errors


def _sections(content: str) -> list[tuple[re.Match, str]]:
    matches = list(SCRIBE_SECTION_RE.finditer(content))
    out = []
    for i, m in enumerate(matches):
        end = matches[i + 1].start() if i + 1 < len(matches) else len(content)
        out.append((m, content[m.end():end]))
    return out


def validate_reader(content: str, *, pool_size: int, min_sections: int) -> list[str]:
    errors: list[str] = []
    sections = _sections(content)
    if not sections:
        return ["No paper sections found. Each source must start with a heading of the "
                "exact form '## Paper N: Title' (or '## N: Title')."]
    numbers = [int(m.group(1)) for m, _ in sections]
    if len(sections) < min_sections:
        errors.append(f"Only {len(sections)} paper sections found; at least "
                      f"{min_sections} are required.")
    if numbers != list(range(1, len(numbers) + 1)):
        errors.append(f"Paper numbering must be contiguous starting at 1 (got {numbers}).")

    seen_sources: dict[int, str] = {}
    for m, body in sections:
        label = f"Paper {m.group(1)}"
        if not AUTHORS_RE.search(body):
            errors.append(f"Section '## {label}: {m.group(2)}' is missing a '**Authors:**' line.")
        if not YEAR_RE.search(body):
            errors.append(f"Section '## {label}' is missing a '**Year:** YYYY' line.")
        src = SOURCE_RE.search(body)
        if not src:
            errors.append(f"Section '## {label}' is missing a '**Source:** #N' line naming its "
                          "row in the harvested citations.")
        else:
            idx = int(src.group(1))
            if not 1 <= idx <= pool_size:
                errors.append(f"Section '## {label}' cites source #{idx}, which is not a harvest "
                              f"row (valid: #1–#{pool_size}). Only harvested sources may appear.")
            elif idx in seen_sources:
                errors.append(f"Source #{idx} is used more than once ({seen_sources[idx]} and "
                              f"{label}) — one section per source.")
            else:
                seen_sources[idx] = label
        depth = READ_DEPTH_RE.search(body)
        if not depth or depth.group(1) not in READ_DEPTHS:
            errors.append(f"Section '## {label}' needs '**Read depth:**' set to one of "
                          f"{', '.join(READ_DEPTHS)}.")
        elif depth.group(1) == "metadata-only" and FINDINGS_HEADING_RE.search(body):
            errors.append(f"Section '## {label}' is metadata-only but reports Findings — "
                          "findings require fetched text. Fetch the abstract, or remove the "
                          "Findings section.")
        if len(body.strip()) < 80:
            errors.append(f"Section '## {label}' body is too thin — include the analysis "
                          "fields from the template.")
    return errors


def _surname(author: str) -> str:
    author = author.strip()
    if "," in author:  # "Smith, J."
        author = author.split(",")[0]
    parts = author.split()
    return (parts[-1] if parts else "").lower()


def extract_citations(content: str) -> list[tuple[str, int, str]]:
    """(surname, year, raw) for every parenthetical author-year citation."""
    found = []
    for paren in _PAREN_RE.finditer(content):
        for chunk in paren.group(1).split(";"):
            m = _CITE_RE.match(chunk)
            if m:
                found.append((m.group("surname").split()[-1].lower(), int(m.group("year")),
                              chunk.strip()))
    # Narrative form: "Smith and Jones (2021)" / "Smith et al. (2021)".
    for m in re.finditer(r"([A-Z][\w'’\-]+)(?:\s+et\s+al\.?|\s+(?:and|&)\s+[A-Z][\w'’\-]+)?"
                         r"\s+\((\d{4})[a-z]?\)", content):
        found.append((m.group(1).lower(), int(m.group(2)), f"{m.group(1)} ({m.group(2)})"))
    return found


def validate_review(content: str, *, papers: list[dict]) -> list[str]:
    errors: list[str] = []
    heads = _heading_lines(content)
    for section in REVIEW_REQUIRED_SECTIONS:
        if not any(section.lower() in h for h in heads):
            errors.append(f"Missing required section heading '## {section}'.")

    known = {(_surname(a), int(p["year"])) for p in papers for a in (p.get("authors") or [])
             if p.get("year")}
    citations = extract_citations(content)
    if not citations:
        errors.append("The review must cite the read sources inline as (Author, Year) — "
                      "none found.")
    unknown = sorted({raw for surname, year, raw in citations if (surname, year) not in known})
    for raw in unknown:
        errors.append(f"Citation ({raw}) does not match any read source (author + year). Cite "
                      "only sources that have notes, with their exact year, or remove the claim.")
    return errors


def validate_signal(content: str) -> list[str]:
    heads = _heading_lines(content)
    errors = []
    positions = []
    for s in SIGNAL_REQUIRED_SECTIONS:
        hits = [i for i, h in enumerate(heads) if s.lower() in h]
        if not hits:
            errors.append(f"Missing required section heading containing '{s}'.")
        elif len(hits) > 1:
            errors.append(f"Section '{s}' appears {len(hits)} times — exactly once.")
        else:
            positions.append(hits[0])
    if not errors and positions != sorted(positions):
        errors.append("Sections must appear in this order: "
                      + " → ".join(SIGNAL_REQUIRED_SECTIONS) + ".")
    return errors


def validate_scout(content: str, *, expected_queries: list[str]) -> list[str]:
    errors: list[str] = []
    sections = SCOUT_QUERY_HEADER_RE.findall(content)
    if len(sections) < len(expected_queries):
        errors.append(f"Need one '## Query: <text>' section per requested query "
                      f"({len(expected_queries)} requested, {len(sections)} found).")
    urls = URL_RE.findall(content)
    if len(urls) < 3:
        errors.append(f"Need at least 3 source URLs across the findings (found {len(urls)}).")
    entry_re = re.compile(r"^- .+\|.+\|.+\|\s*https?://", re.MULTILINE)
    if not entry_re.search(content):
        errors.append("Entries must be markdown bullets of the form "
                      "'- <title> | <publisher> | <year> | <url>'.")
    if re.search(r"\b10\.\d{4,9}/", content):
        errors.append("Do not include DOIs — you find WEB sources; academic citations "
                      "come from the bibliographic APIs.")
    if not SCOUT_COVERAGE_RE.search(content):
        errors.append("Finish with a '## Coverage' section naming any query you could not "
                      "source (or saying all were sourced).")
    return errors
