---
name: deep-research
description: Runs a source-grounded literature review with real, verifiable citations. Use when the user asks for deep research, a literature review, a state-of-the-art or evidence review, a research-gap analysis, a bibliography, "find papers on X", "what does the research say about X", or any answer that must be backed by citations they can check. A bundled pipeline harvests real records from Crossref, OpenAlex and Semantic Scholar, then worker subagents read, review and analyze ONLY what the harvest returned — every step is checked by a validator, and no citation is ever written from memory.
---

# Deep Research

A deterministic pipeline that produces a cited literature review, a gap analysis, and a
bibliography where **every reference traces back to a record a bibliographic API returned
during this run**, and every finding traces back to text that was actually read.

The pipeline — `scripts/pipeline.py` in this skill's directory — is the program counter. It
decides what happens next, builds every worker's brief, and validates every worker's output.
You are the **orchestrator**: you run commands, hand briefs to workers, and move files. You
never write research content yourself, and you never edit a worker's output.

## The one rule that matters

> **No citation exists unless it came back from an API call in this run.**

The pipeline enforces it mechanically: the reader may only take notes on harvest rows, the
review validator rejects any `(Author, Year)` that does not match a source with notes, and a
source nobody could read is tagged `metadata-only` and may not report findings. Your part is
to never route around a validator — a rejection is a correction brief, not an obstacle.

## Requirements

- `uv` (preferred — `pipeline.py` declares its dependencies inline) or `python3` with
  `pydantic>=2` and `requests`.
- Network access to `api.crossref.org`, `api.openalex.org`, `api.semanticscholar.org`, and
  web fetch/search for the workers.
- Optional environment: `OPENALEX_EMAIL` (polite pools — faster, fewer rate limits; ask the
  user before using their address), `OPENALEX_API_KEY`, `SEMANTIC_SCHOLAR_API_KEY`,
  `DEEP_RESEARCH_RUNS_ROOT` (default `~/.local/share/deep-research/runs`).

Below, `PIPE` means `uv run <this skill's directory>/scripts/pipeline.py`. Every command
prints one JSON object.

## Step 1 — Scope (you + the user)

Confirm before spending API calls. Ask in one message; if the user already gave enough, state
your reading and continue.

- **Topic**, sharpened to a researchable question.
- **Depth**:

  | Preset | `--target` | Roughly |
  | --- | --- | --- |
  | `scan` | 10 | quick orientation |
  | `standard` (default) | 25 | review + gaps + bibliography |
  | `deep` | 40 | the same, wider and slower |

- **Web sources** (`--web-scout`): `auto` (default — scout only when the academic harvest is
  short), `always` for practice- or industry-facing topics where indexed literature is thin by
  construction, `never` for strictly peer-reviewed work.

## Step 2 — Start and drive the loop

```bash
PIPE start --topic "<question>" --target 25 --web-scout auto
```

The result carries `run_id`, `out_dir` and `next`. Tell the user the run id. Then act on
`next.kind` until the run is done or failed:

### `kind: dispatch` — a worker step

1. Spawn a **fresh subagent** (general-purpose; the reader and web-scout need web fetch/search).
   Give it `next.action.task_text` **verbatim** — or, for a long brief (the reader's carries the
   whole harvest), tell it to read `next.brief_path`, which holds the identical text, and follow
   it exactly. Add exactly one instruction: *"Write your complete output to
   `<next.output_path>` with the Write tool, then reply with one line confirming it is
   written."* Nothing else — the brief is complete.
2. When it confirms: `PIPE submit <run_id> <next.step_token> <next.output_path>`.
3. **Accepted** → continue with the returned `next`.
4. **Rejected** (`"accepted": false` with `errors`) → send the errors back to the **same**
   worker (continue that subagent if you can; otherwise a fresh one given its previous output
   file plus the errors), telling it to fix exactly those problems and rewrite the whole
   document. Resubmit with the **new** `step_token` from the rejection. Never fix it yourself.
   When `attempts_left` hits 0 the result carries a `note` and a `next` — follow it.

If you have no subagent tool, do the worker step yourself in a separate, clean pass that uses
only `task_text` — and still submit it through the validator.

| Step | Worker | Needs | Produces |
| --- | --- | --- | --- |
| `s0_plan` | planner | — | `plan.json` (6–12 queries, one disconfirming) |
| `s2_scout` | web-scout | web search | `scout_findings.md` (web sources, no DOIs) |
| `s4_read` | reader | web fetch | `reader_output.md` (per-source notes, read-depth tagged) |
| `s6_review` | review-writer | — | `review.md` (thematic review, citations verified) |
| `s7_signal` | signal | — | `signal_output.md` (gap analysis, six ordered sections) |

### `kind: harvest` — the citation harvest

Run `PIPE harvest <run_id>` **in the background** (it can take several minutes — Semantic
Scholar's keyless tier allows one request every two seconds) and wait for it to finish; do not
poll. Its JSON has the harvest `report` (tier, per-query yields, weak queries) and the `next`
step. Tell the user the tier in one line. A crashed or interrupted harvest can simply be re-run:
per-query results are cached in the run directory.

### `kind: done`

Read `next.manifest`. Present the artifacts — `review.md`, `signal_output.md`,
`bibliography.md` (grouped peer-reviewed / preprints / web, each entry with its read depth) —
as files the user can open, and give a short summary: sources read + tier, any `degraded`
steps and what that means, and the single most useful thing the evidence says.

### `kind: failed`

Report `next.error` verbatim and stop. Do not improvise a recovery. The common case is a harvest
below the minimum even after scouting: say plainly that the literature is thin, show what was
found (`PIPE status <run_id>`), and ask whether to broaden the topic.

## Degradation, not fabrication

Three rejected attempts at the review or the gap analysis **degrade** the run: the step is
skipped, recorded in `manifest.degraded`, and the run continues — a bibliography plus honest notes
beats a complete-looking report that isn't. The plan and the reader cannot degrade (nothing
downstream is honest without them), so their exhaustion fails the run. The scout is a pressure
valve: if it exhausts but the harvest already reached the minimum tier, the run proceeds.

## Resume

A run survives a lost conversation. Given a run id: `PIPE status <run_id>`, then `PIPE next
<run_id>`, and re-enter the loop. `next` is idempotent — it re-serves the current step (with the
same token) and does no work.

## Known limits

- The automated harvest covers Crossref, OpenAlex and Semantic Scholar. Europe PMC and arXiv are
  not yet harvested automatically; the reader can still fetch full text from them for harvested
  records, using `references/harvest.md`.
- Tiers: `EXCELLENT` ≥ 100% of target, `ACCEPTABLE` ≥ 86%, `MINIMAL` ≥ 70%, `FAILED` below.

## References

- `references/validators.md` — every contract the pipeline enforces, per step, and the
  bibliography format. Read it when a rejection is unclear.
- `references/harvest.md` — bibliographic API playbook (endpoints, fields, rate limits) for
  fetching text by hand.
- `evals/` — a head-to-head evaluation fixture and scoring rubric.

## Attribution

The citation clients, quality tiers and analysis frameworks derive from
[opendraft](https://github.com/federicodeponte/opendraft) (MIT); see
`scripts/pipeline_core/vendor/VENDORED.md` for what was vendored and patched.
