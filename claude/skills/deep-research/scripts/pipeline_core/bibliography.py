"""Bibliography assembly — deterministic, no LLM.

Converts harvested metadata (+ optional web-scout findings) into the vendored
``CitationDatabase`` and writes ``bibliography.json`` in the upstream
``to_dict`` shape, plus ``bibliography.md`` for people. Improvements over
upstream: cite ids are assigned AFTER dedup/filtering, so ``cite_001..cite_NNN``
are always dense; every entry carries the depth at which it was actually read;
and the human bibliography keeps preprints and web sources visibly apart from
peer-reviewed work.
"""

from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

from .vendor.citation_database import (
    Citation,
    CitationDatabase,
    deduplicate_citations,
    save_citation_database,
)

_SOURCE_TYPES = {"journal", "book", "report", "website", "conference", "case",
                 "statute", "constitution", "treaty"}

SCOUT_ENTRY_RE = re.compile(
    r"^-\s*(?P<title>[^|]+?)\s*\|\s*(?P<publisher>[^|]+?)\s*\|\s*(?P<year>[^|]+?)\s*\|\s*(?P<url>https?://\S+)\s*$",
    re.MULTILINE,
)


def _to_int(value: Any) -> Optional[int]:
    try:
        return int(str(value))
    except (TypeError, ValueError):
        return None


def citation_from_metadata(md: dict, citation_id: str) -> Optional[Citation]:
    authors = [a for a in (md.get("authors") or []) if a]
    year = _to_int(md.get("year"))
    title = (md.get("title") or "").strip()
    if not authors or not year or not title:
        return None
    source_type = md.get("source_type") or "journal"
    if source_type not in _SOURCE_TYPES:
        source_type = "journal"
    return Citation(
        citation_id=citation_id,
        authors=authors,
        year=year,
        title=title,
        source_type=source_type,
        journal=md.get("journal") or None,
        publisher=md.get("publisher") or None,
        volume=_to_int(md.get("volume")),
        issue=_to_int(md.get("issue")),
        pages=md.get("pages") or None,
        doi=md.get("doi") or None,
        url=md.get("url") or None,
        api_source=md.get("api_source") or None,
        citation_count=_to_int(md.get("citation_count")),
    )


def scout_findings_to_metadata(findings_md: str) -> list[dict]:
    """Parse web-scout entries ('- title | publisher | year | url') into
    harvest-shaped metadata dicts (source_type=website)."""
    current_year = datetime.now(timezone.utc).year
    out: list[dict] = []
    for m in SCOUT_ENTRY_RE.finditer(findings_md):
        year = _to_int(m.group("year")) or current_year
        publisher = m.group("publisher").strip()
        out.append(
            {
                "title": m.group("title").strip(),
                "authors": [publisher],  # web sources: publisher stands as author
                "year": year,
                "publisher": publisher,
                "url": m.group("url").strip(),
                "source_type": "website",
                "api_source": "web-scout",
            }
        )
    return out


PREPRINT_DOI_PREFIXES = ("10.48550/", "10.1101/", "10.2139/ssrn", "10.21203/rs.")
PREPRINT_VENUE_RE = re.compile(r"arxiv|biorxiv|medrxiv|ssrn|preprint|research square", re.I)

GROUPS = (("peer", "Peer-reviewed sources"), ("preprint", "Preprints"),
          ("web", "Web and industry sources"))


def classify(entry: dict) -> str:
    """'web', 'preprint' or 'peer' for a bibliography.json citation dict."""
    if entry.get("api_source") == "web-scout" or entry.get("source_type") == "website":
        return "web"
    doi = (entry.get("doi") or "").lower()
    if (entry.get("source_type") == "preprint" or doi.startswith(PREPRINT_DOI_PREFIXES)
            or PREPRINT_VENUE_RE.search(entry.get("journal") or "")):
        return "preprint"
    return "peer"


def _format_entry(entry: dict, group: str) -> str:
    authors = entry.get("authors") or []
    if len(authors) > 2:
        names = ", ".join(authors[:-1]) + f", & {authors[-1]}"
    else:
        names = " & ".join(authors)
    line = f"- `{entry['id']}` {names} ({entry.get('year')}). {entry.get('title')}."
    if group != "web" and entry.get("journal"):
        line += f" *{entry['journal']}*."
    if group == "web" and entry.get("publisher") and entry.get("publisher") not in authors:
        line += f" {entry['publisher']}."
    if group != "web" and entry.get("doi"):
        line += f" https://doi.org/{entry['doi']}"
    elif entry.get("url"):
        line += f" {entry['url']}"
    if group == "preprint":
        line += " [PREPRINT]"
    line += f" — read: {entry.get('read_depth', 'metadata-only')}"
    return line


def render_markdown(citations: list[dict], citation_style: str) -> str:
    lines = [f"# Bibliography ({citation_style})", "",
             f"{len(citations)} sources. Each entry notes the depth at which it was read.", ""]
    for key, heading in GROUPS:
        members = [c for c in citations if classify(c) == key]
        lines += [f"## {heading}", ""]
        lines += [_format_entry(c, key) for c in members] or ["_None._"]
        lines.append("")
    return "\n".join(lines)


def build_bibliography(
    metadata_pool: list[dict],
    out_path: Path,
    citation_style: str = "APA 7th",
    read_depth: Optional[dict[int, str]] = None,
) -> dict[str, Any]:
    """Write ``out_path`` (JSON) and its ``.md`` sibling.

    ``read_depth`` maps 1-based positions in ``metadata_pool`` to the depth the
    reader recorded; unmapped sources are ``metadata-only``.
    """
    read_depth = read_depth or {}
    provisional = []
    depth_by_tmp: dict[str, str] = {}
    for i, md in enumerate(metadata_pool, start=1):
        cit = citation_from_metadata(md, f"tmp_{i:03d}")
        if cit is not None:
            provisional.append(cit)
            depth_by_tmp[cit.id] = read_depth.get(i, "metadata-only")

    deduped = deduplicate_citations(provisional)
    depth_by_final: dict[str, str] = {}
    for i, cit in enumerate(deduped, start=1):
        final_id = f"cite_{i:03d}"  # dense ids AFTER dedup (upstream leaves gaps)
        depth_by_final[final_id] = depth_by_tmp.get(cit.id, "metadata-only")
        cit.id = final_id

    db = CitationDatabase(citations=deduped, citation_style=citation_style)
    save_citation_database(db, out_path)

    data = json.loads(out_path.read_text(encoding="utf-8"))
    for entry in data["citations"]:
        entry["read_depth"] = depth_by_final[entry["id"]]
    out_path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
    out_path.with_suffix(".md").write_text(render_markdown(data["citations"], citation_style),
                                           encoding="utf-8")

    # Self-check invariants (validator for the deterministic step).
    ids = [c["id"] for c in data["citations"]]
    assert ids == [f"cite_{i:03d}" for i in range(1, len(ids) + 1)], "non-dense cite ids"
    return {"citations": len(ids), "dropped_incomplete": len(metadata_pool) - len(provisional)}
