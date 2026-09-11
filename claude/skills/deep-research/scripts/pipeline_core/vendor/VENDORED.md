# Vendored: opendraft 1.7.4 citation layer

**Upstream:** [federicodeponte/opendraft](https://github.com/federicodeponte/opendraft), MIT license (see `LICENSE`).
**Source artifact:** PyPI wheel `opendraft-1.7.4-py3-none-any.whl`
sha256 `d7fe5a496734939025b4ef2fa4f6cd4279372d17f9ca016e570f0f73556912d1`
Extraction: `pip download opendraft==1.7.4 --no-deps` (2026-08-01).

## Files (wheel path → here)

| Upstream (wheel) | Vendored | Patched? |
| --- | --- | --- |
| `utils/models.py` | `models.py` | no |
| `utils/citation_database.py` | `citation_database.py` | no |
| `utils/api_citations/base.py` | `api_citations/base.py` | **yes** (2) |
| `utils/api_citations/crossref.py` | `api_citations/crossref.py` | **yes** (3) |
| `utils/api_citations/openalex.py` | `api_citations/openalex.py` | **yes** (2, 4) |
| `utils/api_citations/semantic_scholar.py` | `api_citations/semantic_scholar.py` | **yes** (3) |
| `utils/api_citations/query_router.py` | `api_citations/query_router.py` | **yes** (1) |
| `utils/api_citations/__init__.py` | `api_citations/__init__.py` | **rewritten** |

## Local patches

Marked `local vendor patch` / `Local patch` in-line.

1. **`query_router.py` — keyless-only chains.** `gemini_grounded` removed from
   `APIName` and every chain (web/industry coverage moved to the pipeline-level
   `web-scout` worker); `openalex` added — upstream defined `OpenAlexClient`
   but `get_api_chain` never emitted it, leaving it dead code.
2. **`base.py` — request hygiene.** Upstream rotated a pool of spoofed browser
   User-Agents on every request, forwarded a client IP in `X-Forwarded-For`, and
   rotated through `PROXY_LIST` proxies with near-zero backoff — rate-limit
   evasion, not rate-limit respect. All removed, along with the inert
   `utils.backpressure` hook and the unused SSRF/proxy helpers. Every request now
   identifies as this tool (`deep-research-skill/…`, plus `mailto:` from
   `OPENALEX_EMAIL` for the Crossref/OpenAlex polite pools), and rate limits are
   met with backoff. `validate_author_name` now matches its generic terms as whole
   words — upstream's substring test silently dropped real authors such as
   *Stafford* (`staff`) or *Teamey* (`team`). Side effect worth knowing: upstream's per-request browser
   User-Agent *overrode* OpenAlex's polite-pool header, so the polite pool never
   actually engaged. Also: OpenAlex's anonymous limiter answers **HTTP 200** with
   `{"error": …, "retryAfter": N}`; upstream parsed that as "no results" — the likeliest
   reason OpenAlex contributed zero records to both recorded runs of the previous
   deployment. It is now retried.
3. **`crossref.py`, `semantic_scholar.py` — `search_papers(query, limit)`.**
   Upstream parsed only `items[0]`, so a query yielded at most one record per API
   and one incomplete top hit discarded the response. `search_paper` now
   delegates to `search_papers` (first usable record).
4. **`openalex.py`.** The hard-coded fallback polite-pool address is removed (the
   header comes from patch 2). Paging uses `per-page`, the documented spelling
   (OpenAlex also accepts `per_page`; verified live 2026-09-10).

## Deliberately NOT vendored (and why)

- `utils/api_citations/orchestrator.py` — Gemini-entangled `CitationResearcher`
  with a CWD-relative cache file rewritten O(n²) per query and a hidden
  verbosity module-global. Replaced by `pipeline_core/harvest.py` (run-dir
  cache, no globals, configurable early-stop).
- `utils/api_citations/{gemini_grounded,serper_client,dataforseo_client}.py` —
  keyed clients; out of scope (keyless principle).
- `utils/agent_runner.py` — Gemini-shaped response unpacking, blind-resample
  retry, hard-coded `/tmp` debug logs. Replaced by the pipeline state machine
  (corrective retry: validator errors fed back).
- `utils/checkpoint.py` — phase-level only; the pipeline needs step-level
  checkpoints with step tokens (`pipeline_core/state.py`).

Upgrade procedure: bump the wheel pin, re-extract, re-copy, re-apply patches 1–4
(grep for `ocal vendor patch` / `Local patch`), update the sha256 above, run
`pipeline_core/tests/` — fixture and request-hygiene tests must stay green.
