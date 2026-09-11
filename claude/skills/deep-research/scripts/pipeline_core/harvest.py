"""Keyless citation harvest — replaces opendraft's Gemini-entangled
``CitationResearcher`` orchestrator for the research pipeline.

Fixes carried over from the upstream landmine list:
- per-query cache lives under the RUN directory (upstream: CWD-relative file
  rewritten wholesale after every query);
- no debug writes to /tmp; no module-global verbosity;
- early-stop is derived from the target (upstream: hard-coded 50);
- each API contributes every usable record in its top results, and the chain
  is walked until the per-query quota is met (upstream kept one record per API);
- Semantic Scholar's keyless tier gets two attempts, not five — at 3·2ⁿ s
  backoff, five attempts could stall a single query for ~90 s.
"""

from __future__ import annotations

import hashlib
import json
import os
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any, Optional

from .vendor.api_citations import (
    CrossrefClient,
    OpenAlexClient,
    QueryRouter,
    SemanticScholarClient,
)
from .vendor.api_citations.base import validate_author_name, validate_publication_year

TIER_EXCELLENT = "EXCELLENT"
TIER_ACCEPTABLE = "ACCEPTABLE"
TIER_MINIMAL = "MINIMAL"
TIER_FAILED = "FAILED"

# Upstream gate ratios (agent_runner.research_citations_via_api, 1.7.4).
ACCEPTABLE_RATIO = 0.86
MINIMAL_RATIO = 0.70


def passes_quality_gate(md: dict) -> bool:
    """Drop records with no title, no author, an institutional or URL-shaped first
    author, or a missing / future / pre-1900 year. Applied to every API alike —
    upstream only checked author names in two of the three clients, and never
    called its own year validator."""
    authors = md.get("authors") or []
    if not (md.get("title") or "").strip() or not authors:
        return False
    if not validate_author_name(str(authors[0]))[0]:
        return False
    return validate_publication_year(md.get("year"))[0]


def tier_for(accepted: int, target: int) -> str:
    if accepted >= target:
        return TIER_EXCELLENT
    if accepted >= int(target * ACCEPTABLE_RATIO):
        return TIER_ACCEPTABLE
    if accepted >= int(target * MINIMAL_RATIO):
        return TIER_MINIMAL
    return TIER_FAILED


class Harvester:
    def __init__(
        self,
        cache_dir: Path,
        openalex_email: Optional[str] = None,
        max_workers: int = 3,
        results_per_query: int = 5,
    ):
        self.cache_dir = cache_dir
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.max_workers = max_workers
        self.results_per_query = results_per_query
        if openalex_email:
            os.environ.setdefault("OPENALEX_EMAIL", openalex_email)
        self.router = QueryRouter()
        self.clients = {
            "crossref": CrossrefClient(),
            "openalex": OpenAlexClient(),
            "semantic_scholar": SemanticScholarClient(max_retries=2),
        }

    # -- caching -----------------------------------------------------------

    def _cache_path(self, query: str) -> Path:
        return self.cache_dir / (hashlib.sha256(query.lower().encode()).hexdigest()[:24] + ".json")

    def _cached(self, query: str) -> Optional[dict]:
        path = self._cache_path(query)
        if path.exists():
            try:
                return json.loads(path.read_text(encoding="utf-8"))
            except ValueError:
                return None
        return None

    def _store(self, query: str, entry: dict) -> None:
        self._cache_path(query).write_text(json.dumps(entry), encoding="utf-8")

    # -- harvesting --------------------------------------------------------

    def _harvest_query(self, query: str) -> dict:
        """{"results": [...], "dropped": n} — cached per query in the run directory."""
        cached = self._cached(query)
        if cached is not None:
            return cached
        results: list[dict] = []
        dropped = 0
        chain = self.router.classify_and_route(query).api_chain
        for api in chain:
            client = self.clients.get(api)
            if client is None:
                continue
            try:
                found = client.search_papers(query, limit=self.results_per_query)
            except Exception:  # noqa: BLE001 — per-source tolerance
                continue
            for metadata in found:
                if not (metadata.get("doi") or metadata.get("url")):
                    continue
                if not passes_quality_gate(metadata):
                    dropped += 1
                    continue
                metadata["api_source"] = api
                metadata["query"] = query
                results.append(metadata)
                if len(results) >= self.results_per_query:
                    break
            if len(results) >= self.results_per_query:
                break
        entry = {"results": results, "dropped": dropped}
        self._store(query, entry)
        return entry

    def harvest(self, queries: list[str], target: int) -> dict[str, Any]:
        """Run every query, then fill the pool round-robin in plan order.

        Returns {citations, report}. The cap is ``max(2 × target, 20)``. Upstream
        stopped consuming results once the cap was hit in *completion* order — but
        the executor still ran every query, so the calls were paid for and the late
        queries (often the disconfirming one, which planners list last) silently
        contributed nothing. Round-robin keeps every query represented and makes the
        pool independent of network timing.
        """
        cap = max(2 * target, 20)
        entries: dict[str, dict] = {}
        with ThreadPoolExecutor(max_workers=self.max_workers) as ex:
            futures = {ex.submit(self._harvest_query, q): q for q in queries}
            for fut in as_completed(futures):
                try:
                    entries[futures[fut]] = fut.result()
                except Exception:  # noqa: BLE001
                    entries[futures[fut]] = {"results": [], "dropped": 0}

        per_query = {q: len(entries[q]["results"]) for q in queries}
        pool: list[dict] = []
        seen_keys: set[tuple] = set()
        depth = max(per_query.values(), default=0)
        for rank in range(depth):
            for q in queries:
                results = entries[q]["results"]
                if rank >= len(results) or len(pool) >= cap:
                    continue
                md = results[rank]
                key = (
                    (md.get("authors") or [""])[0].lower(),
                    md.get("year"),
                    (md.get("title") or "").lower(),
                )
                if key in seen_keys:
                    continue
                seen_keys.add(key)
                pool.append(md)

        accepted = len(pool)
        report = {
            "target": target,
            "accepted": accepted,
            "tier": tier_for(accepted, target),
            "pool_cap": cap,
            "candidates": sum(per_query.values()),
            "dropped_quality": sum(e["dropped"] for e in entries.values()),
            "per_query": per_query,
            "weak_queries": [q for q in queries if per_query[q] == 0],
        }
        return {"citations": pool, "report": report}
