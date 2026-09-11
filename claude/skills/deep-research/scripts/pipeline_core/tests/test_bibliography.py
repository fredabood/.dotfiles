"""Bibliography assembly: dense ids, read depth, and grouped markdown (offline)."""

from __future__ import annotations

import json

from pipeline_core import bibliography as biblio


def _md(title, **kw):
    base = {"title": title, "authors": ["Smith"], "year": 2022, "journal": "Journal of X",
            "doi": f"10.1/{title}", "url": f"https://doi.org/10.1/{title}",
            "api_source": "crossref"}
    return {**base, **kw}


POOL = [
    _md("peer"),
    _md("arxiv", journal="arXiv", doi="10.48550/arXiv.2101.00001"),
    _md("biorxiv", doi="10.1101/2022.01.01.123456", journal=None),
    {"title": "Industry report", "authors": ["Gartner"], "year": 2024, "publisher": "Gartner",
     "url": "https://gartner.com/r", "source_type": "website", "api_source": "web-scout"},
]


def test_groups_sources_into_peer_reviewed_preprint_and_web(tmp_path):
    stats = biblio.build_bibliography(POOL, tmp_path / "bibliography.json",
                                      read_depth={1: "full-text", 2: "abstract"})
    assert stats["citations"] == 4
    md = (tmp_path / "bibliography.md").read_text()
    peer, rest = md.split("## Preprints")
    preprints, web = rest.split("## Web and industry sources")
    assert "## Peer-reviewed sources" in peer and "peer" in peer
    assert "arxiv" in preprints and "biorxiv" in preprints and "[PREPRINT]" in preprints
    assert "Industry report" in web and "10.1" not in web

    data = json.loads((tmp_path / "bibliography.json").read_text())
    depth = {c["title"]: c.get("read_depth") for c in data["citations"]}
    assert depth["peer"] == "full-text" and depth["arxiv"] == "abstract"
    assert depth["Industry report"] == "metadata-only"
    assert [c["id"] for c in data["citations"]] == ["cite_001", "cite_002", "cite_003", "cite_004"]
