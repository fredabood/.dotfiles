"""Deterministic scribe-output splitter — port of opendraft 1.7.4
``phases/research.py::split_scribe_to_papers`` (regex frozen; validators.py
guarantees splittability before this ever runs). Prints removed; returns paths.
"""

from __future__ import annotations

import re
from pathlib import Path

from .validators import SCRIBE_SECTION_RE


def _slugify(text: str, max_length: int = 30) -> str:
    slug = re.sub(r"[^\w\s-]", "", text.lower())
    slug = re.sub(r"[\s_]+", "_", slug).strip("_")
    return slug[:max_length]


def split_scribe_to_papers(scribe_output: str, papers_dir: Path) -> list[Path]:
    papers_dir.mkdir(parents=True, exist_ok=True)
    created: list[Path] = []
    matches = list(SCRIBE_SECTION_RE.finditer(scribe_output))
    for i, match in enumerate(matches):
        start = match.start()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(scribe_output)
        body = scribe_output[start:end].strip()

        author_match = re.search(r"\*\*Authors?:\*\*\s*([^*\n]+)", body)
        year_match = re.search(r"\*\*Year:\*\*\s*(\d{4})", body)
        author = _slugify(author_match.group(1).split(",")[0] if author_match else "unknown", 15)
        year = year_match.group(1) if year_match else "na"
        title_slug = _slugify(match.group(2), 40)

        path = papers_dir / f"paper_{int(match.group(1)):03d}_{author}_{year}_{title_slug}.md"
        path.write_text(body, encoding="utf-8")
        created.append(path)
    return created
