"""The deep-research state machine.

Program counter = checkpoint.json. ``next_step`` runs quick deterministic steps
inline and only ever surfaces a WORKER DISPATCH, the HARVEST command, or a
terminal state: the orchestrating agent never writes step content itself.
``submit`` validates a worker's output; rejections return the validator errors
verbatim as the correction brief and rotate the step token (corrective retry —
upstream opendraft resampled blindly).

Step graph:
    s0_plan(planner) -> s1_harvest(command)
    -> [s2_scout(web-scout) -> s3_merge(det)]
    -> s4_read(reader) -> s5_split(det) -> s6_review(review-writer)
    -> s7_signal(signal) -> s8_biblio(det) -> s9_done

The harvest is a separate command because it is slow by design (keyless API
tiers, Semantic Scholar at 0.5 req/s) and must be runnable in the background.
"""

from __future__ import annotations

import json
import re
import secrets
import shutil
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

from . import bibliography as biblio
from . import prompts, validators
from .harvest import TIER_EXCELLENT, TIER_FAILED, Harvester, tier_for
from .splitter import split_scribe_to_papers
from .state import (
    STATE_AWAITING,
    STATE_DONE,
    STATE_FAILED,
    STATE_HARVEST,
    Checkpoint,
    load_checkpoint,
    run_dir_for,
    run_lock,
    save_checkpoint,
)
from .truncate import truncate_paragraphs

MAX_ATTEMPTS = {"s0_plan": 3, "s2_scout": 2, "s4_read": 3, "s6_review": 3, "s7_signal": 3}
DISPATCH_WORKER = {"s0_plan": "planner", "s2_scout": "web-scout", "s4_read": "reader",
                   "s6_review": "review-writer", "s7_signal": "signal"}
OUTPUT_FILE = {"s0_plan": "plan.json", "s2_scout": "scout_findings.md",
               "s4_read": "reader_output.md", "s6_review": "review.md",
               "s7_signal": "signal_output.md"}
ARTIFACT_KEY = {"s0_plan": "plan", "s2_scout": "scout_findings", "s4_read": "reader_output",
                "s6_review": "review", "s7_signal": "signal"}
NEXT_AFTER_ACCEPT = {"s0_plan": "s1_harvest", "s2_scout": "s3_merge", "s4_read": "s5_split",
                     "s6_review": "s7_signal", "s7_signal": "s8_biblio"}
# Steps whose exhaustion degrades the run (skipped, recorded, run continues)
# rather than failing it: later steps can still produce something honest.
DEGRADABLE = ("s6_review", "s7_signal")
WEB_SCOUT_MODES = ("auto", "always", "never")
MAX_SCOUT_QUERIES = 5
CORPUS_BUDGET = 120_000

DISPATCH_INSTRUCTIONS = (
    "Give task_text VERBATIM to a fresh subagent acting as the named worker — for a long brief, "
    "point it at brief_path, which holds the identical text (or, with no "
    "subagent tool, produce it yourself in a separate pass that follows task_text alone). "
    "Write the worker's complete reply to output_path, then run: "
    "pipeline.py submit <run_id> <step_token> <output_path>. Never edit the content yourself."
)


class PipelineError(Exception):
    pass


# --------------------------------------------------------------------------
# payload builders (dispatch steps)
# --------------------------------------------------------------------------

def _load_pool(run_dir: Path) -> list[dict]:
    return json.loads((run_dir / "citations_raw.json").read_text(encoding="utf-8"))


def _corpus_markdown(pool: list[dict]) -> str:
    lines = ["# Harvested Citations\n"]
    for i, md in enumerate(pool, start=1):
        abstract = (md.get("abstract") or "").strip()
        lines.append(f"#### #{i}. {md.get('title', '')}")
        lines.append(f"- Authors: {', '.join(md.get('authors') or [])}")
        lines.append(f"- Year: {md.get('year')}  |  Venue: {md.get('journal') or md.get('publisher') or 'n/a'}")
        lines.append(f"- DOI: {md.get('doi') or 'n/a'}  |  URL: {md.get('url') or 'n/a'}")
        if md.get("citation_count") is not None:
            lines.append(f"- Citations: {md.get('citation_count')}")
        lines.append(f"- Source: {md.get('api_source', 'n/a')}  |  Found via query: {md.get('query', 'n/a')}")
        lines.append(f"- Evidence available: {'abstract' if abstract else 'metadata-only'}")
        if abstract:
            lines.append(f"- Abstract: {abstract}")
        lines.append("")
    return "\n".join(lines)


def _weak_queries(cp: Checkpoint) -> list[str]:
    return ((cp.harvest or {}).get("weak_queries") or [])[:MAX_SCOUT_QUERIES] or [cp.topic]


def _papers_digest(run_dir: Path) -> str:
    return "\n\n".join(p.read_text(encoding="utf-8")
                       for p in sorted((run_dir / "papers").glob("paper_*.md")))


def _plan_outline(run_dir: Path) -> str:
    try:
        from .vendor.models import strip_markdown_json
        plan = json.loads(strip_markdown_json((run_dir / "plan.json").read_text(encoding="utf-8")))
        return str(plan.get("outline") or "")
    except (OSError, ValueError):
        return ""


def _build_task_text(cp: Checkpoint, run_dir: Path, step_id: str) -> str:
    if step_id == "s0_plan":
        return prompts.planner_prompt(cp.topic, cp.target_citations)
    if step_id == "s2_scout":
        report = cp.harvest or {}
        deficit = max(0, cp.target_citations - int(report.get("accepted", 0)))
        return prompts.scout_prompt(cp.topic, _weak_queries(cp), deficit,
                                    int(report.get("accepted", 0)), cp.target_citations)
    if step_id == "s4_read":
        corpus = truncate_paragraphs(_corpus_markdown(_load_pool(run_dir)), CORPUS_BUDGET)
        (run_dir / "reader_input.md").write_text(corpus, encoding="utf-8")
        return prompts.reader_prompt(cp.topic, corpus)
    if step_id == "s6_review":
        report = cp.harvest or {}
        context = (f"Tier: {report.get('tier')} · harvested {report.get('accepted')} of target "
                   f"{cp.target_citations} · queries with no results: "
                   f"{report.get('weak_queries') or 'none'}")
        return prompts.review_prompt(cp.topic, _plan_outline(run_dir), context,
                                     truncate_paragraphs(_papers_digest(run_dir), CORPUS_BUDGET))
    if step_id == "s7_signal":
        review_path = run_dir / OUTPUT_FILE["s6_review"]
        review = review_path.read_text(encoding="utf-8") if "review" in cp.artifacts else ""
        return prompts.signal_prompt(cp.topic, truncate_paragraphs(_papers_digest(run_dir),
                                                                   CORPUS_BUDGET), review)
    raise PipelineError(f"no payload builder for {step_id}")  # pragma: no cover


def _read_papers(run_dir: Path, cp: Checkpoint) -> list[dict]:
    """Author/year pairs a review may cite: the reader's sections plus the
    harvest rows they point at (the two spell names differently often enough)."""
    papers: list[dict] = []
    for path in sorted((run_dir / "papers").glob("paper_*.md")):
        body = path.read_text(encoding="utf-8")
        authors = validators.AUTHORS_RE.search(body)
        year = validators.YEAR_RE.search(body)
        if authors and year:
            names = re.split(r",|;|&|\band\b", authors.group(1))
            papers.append({"authors": [n for n in (s.strip() for s in names) if n],
                           "year": int(year.group(1))})
    pool = _load_pool(run_dir)
    for idx in cp.read_sources:
        md = pool[int(idx) - 1]
        if md.get("year"):
            papers.append({"authors": md.get("authors") or [], "year": int(md["year"])})
    return papers


def _validate(cp: Checkpoint, run_dir: Path, step_id: str, content: str) -> list[str]:
    if step_id == "s0_plan":
        return validators.validate_plan(content)
    if step_id == "s2_scout":
        return validators.validate_scout(content, expected_queries=_weak_queries(cp))
    if step_id == "s4_read":
        pool_size = len(_load_pool(run_dir))
        return validators.validate_reader(content, pool_size=pool_size,
                                          min_sections=min(5, max(1, pool_size)))
    if step_id == "s6_review":
        return validators.validate_review(content, papers=_read_papers(run_dir, cp))
    if step_id == "s7_signal":
        return validators.validate_signal(content)
    raise PipelineError(f"no validator for {step_id}")  # pragma: no cover


# --------------------------------------------------------------------------
# deterministic steps — each returns (next_step_id, facts to record)
# --------------------------------------------------------------------------

def _route_after_harvest(cp: Checkpoint) -> str:
    report = cp.harvest or {}
    tier = report.get("tier")
    if cp.web_scout == "always":
        return "s2_scout"
    if cp.web_scout == "never":
        if tier == TIER_FAILED:
            raise PipelineError(
                f"harvest below MINIMAL ({report.get('accepted')}/{cp.target_citations}) and "
                f"web_scout=never. Weakest queries: {report.get('weak_queries', [])[:5]}")
        return "s4_read"
    # auto: scout when the academic harvest is short, never because of wording.
    if tier == TIER_FAILED or (report.get("weak_queries") and tier != TIER_EXCELLENT):
        return "s2_scout"
    return "s4_read"


def _run_merge(cp: Checkpoint, run_dir: Path) -> tuple[str, dict]:
    findings = (run_dir / "scout_findings.md").read_text(encoding="utf-8")
    extra = biblio.scout_findings_to_metadata(findings)
    pool = _load_pool(run_dir)
    known_urls = {md.get("url") for md in pool}
    added = [md for md in extra if md["url"] not in known_urls]
    pool.extend(added)
    (run_dir / "citations_raw.json").write_text(json.dumps(pool, indent=2), encoding="utf-8")
    report = dict(cp.harvest or {})
    report["accepted"] = len(pool)
    report["tier"] = tier_for(len(pool), cp.target_citations)
    report["scout_added"] = len(added)
    cp.harvest = report
    (run_dir / "harvest_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    if report["tier"] == TIER_FAILED:
        raise PipelineError(
            f"harvest below MINIMAL even after web-scout: {report['accepted']}/"
            f"{cp.target_citations}. Weakest queries: {report.get('weak_queries', [])[:5]}. "
            "The literature is thin — tell the user and ask whether to broaden the topic.")
    return "s4_read", {"scout_added": len(added), "tier": report["tier"]}


def _run_split(cp: Checkpoint, run_dir: Path) -> tuple[str, dict]:
    content = (run_dir / OUTPUT_FILE["s4_read"]).read_text(encoding="utf-8")
    created = split_scribe_to_papers(content, run_dir / "papers")
    sections = validators._sections(content)
    if len(created) != len(sections) or not created:
        raise PipelineError(f"split mismatch: {len(sections)} sections vs {len(created)} files")
    read_sources: dict[str, str] = {}
    for _, body in sections:
        src = validators.SOURCE_RE.search(body)
        depth = validators.READ_DEPTH_RE.search(body)
        if src and depth:
            read_sources[src.group(1)] = depth.group(1)
    cp.read_sources = read_sources
    cp.artifacts["papers_dir"] = "papers"
    depths = sorted(read_sources.values())
    return "s6_review", {"papers": len(created),
                         "read_depth": {d: depths.count(d) for d in set(depths)}}


def _run_biblio(cp: Checkpoint, run_dir: Path) -> tuple[str, dict]:
    pool = _load_pool(run_dir)
    if cp.read_sources:
        order = sorted(cp.read_sources, key=int)
        subset = [pool[int(i) - 1] for i in order]
        depth = {pos: cp.read_sources[i] for pos, i in enumerate(order, start=1)}
    else:
        subset, depth = pool, {}
    stats = biblio.build_bibliography(subset, run_dir / "bibliography.json", read_depth=depth)
    cp.artifacts["bibliography"] = "bibliography.json"
    cp.artifacts["bibliography_md"] = "bibliography.md"
    return "s9_done", stats


DETERMINISTIC = {"s3_merge": _run_merge, "s5_split": _run_split, "s8_biblio": _run_biblio}


# --------------------------------------------------------------------------
# drive loop
# --------------------------------------------------------------------------

def _serve(cp: Checkpoint, run_dir: Path) -> dict[str, Any]:
    step_id = cp.current_step
    base = {"run_id": cp.run_id, "step_id": step_id}
    if cp.state == STATE_DONE:
        manifest = json.loads((run_dir / "manifest.json").read_text(encoding="utf-8"))
        return {**base, "step_id": "s9_done", "kind": "done", "manifest": manifest}
    if cp.state == STATE_FAILED:
        return {**base, "kind": "failed", "error": cp.failure}
    if cp.state == STATE_HARVEST:
        return {**base, "kind": "harvest", "command": f"pipeline.py harvest {cp.run_id}",
                "instructions": "Run the command (in the background — it can take several "
                                "minutes), then continue with the 'next' it returns."}
    task_text = _build_task_text(cp, run_dir, step_id)
    brief = run_dir / "briefs" / f"{step_id}.md"
    brief.parent.mkdir(parents=True, exist_ok=True)
    brief.write_text(task_text, encoding="utf-8")
    return {
        **base,
        "kind": "dispatch",
        "step_token": cp.step_token,
        "action": {
            "worker": cp.designated_worker,
            "task_text": task_text,
            "expect": OUTPUT_FILE[step_id],
        },
        "brief_path": str(brief),
        "output_path": str(run_dir / OUTPUT_FILE[step_id]),
        "instructions": DISPATCH_INSTRUCTIONS,
    }


def _finish_done(cp: Checkpoint, run_dir: Path) -> None:
    manifest = {
        "run_id": cp.run_id,
        "topic": cp.topic,
        "tier": (cp.harvest or {}).get("tier"),
        "citations": (cp.harvest or {}).get("accepted"),
        "sources_read": len(cp.read_sources),
        "web_scout": cp.web_scout,
        "degraded": list(cp.degraded),
        "artifacts": {k: str(run_dir / v) for k, v in cp.artifacts.items()},
        "attempts": cp.attempts,
        "completed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    (run_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    cp.finish(STATE_DONE)


def _fail(cp: Checkpoint, step_id: str, errors: list[str]) -> None:
    cp.record(step_id, "failed", errors=errors)
    cp.finish(STATE_FAILED, {"step": step_id, "errors": errors})


def _drain(cp: Checkpoint, run_dir: Path) -> None:
    """Run deterministic steps until a dispatch or the harvest is armed, or terminal."""
    while True:
        step_id = cp.current_step
        if step_id == "s9_done":
            _finish_done(cp, run_dir)
            return
        if step_id == "s1_harvest":
            cp.await_harvest()
            return
        if step_id in DISPATCH_WORKER:
            if cp.state != STATE_AWAITING or not cp.step_token:
                cp.arm_dispatch(step_id, DISPATCH_WORKER[step_id])
            return
        try:
            next_id, facts = DETERMINISTIC[step_id](cp, run_dir)
        except PipelineError as exc:
            _fail(cp, step_id, [str(exc)])
            return
        cp.record(step_id, "completed", **facts)
        cp.current_step = next_id
        cp.state = "advancing"


def _advance(cp: Checkpoint, run_dir: Path, next_id: str) -> dict[str, Any]:
    cp.current_step = next_id
    cp.state = "advancing"
    cp.step_token = None
    cp.designated_worker = None
    _drain(cp, run_dir)
    return _serve(cp, run_dir)


# --------------------------------------------------------------------------
# public API (called by ../pipeline.py)
# --------------------------------------------------------------------------

def start(
    runs_root: Path,
    topic: str,
    target_citations: int = 30,
    out_dir: Optional[str] = None,
    openalex_email: Optional[str] = None,
    web_scout: str = "auto",
) -> dict[str, Any]:
    topic = (topic or "").strip()
    if not topic:
        raise PipelineError("topic must be non-empty")
    if target_citations < 3:
        raise PipelineError("target_citations must be >= 3")
    if web_scout not in WEB_SCOUT_MODES:
        raise PipelineError(f"web_scout must be one of {WEB_SCOUT_MODES}")
    runs_root = runs_root.expanduser()
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    run_id = f"dr-{stamp}-{secrets.token_hex(3)}"
    run_dir = Path(out_dir).expanduser() if out_dir else run_dir_for(runs_root, run_id)
    if runs_root.resolve() not in run_dir.resolve().parents:
        raise PipelineError(
            f"out_dir must live under runs_root ({runs_root}) — runs are addressed by id "
            "within it.")
    with run_lock(run_dir):
        cp = Checkpoint(run_id=run_id, topic=topic, target_citations=target_citations,
                        out_dir=str(run_dir), openalex_email=openalex_email,
                        web_scout=web_scout)
        cp.arm_dispatch("s0_plan", "planner")
        nxt = _serve(cp, run_dir)
        save_checkpoint(cp, run_dir)
    return {"run_id": run_id, "out_dir": str(run_dir), "next": nxt}


def _resolve_run_dir(runs_root: Path, run_id: str) -> Path:
    run_dir = run_dir_for(runs_root.expanduser(), run_id)
    if not (run_dir / "checkpoint.json").exists():
        raise PipelineError(f"unknown run_id {run_id!r} under {runs_root}")
    return run_dir


def next_step(runs_root: Path, run_id: str) -> dict[str, Any]:
    run_dir = _resolve_run_dir(runs_root, run_id)
    with run_lock(run_dir):
        cp = load_checkpoint(run_dir)
        nxt = _serve(cp, run_dir)
        save_checkpoint(cp, run_dir)
    return nxt


def harvest(runs_root: Path, run_id: str) -> dict[str, Any]:
    """Run the citation harvest. Slow; holds the run lock only to read and write
    state, so status/next stay responsive. Re-running after a crash is safe —
    per-query results are cached in the run directory."""
    run_dir = _resolve_run_dir(runs_root, run_id)
    with run_lock(run_dir):
        cp = load_checkpoint(run_dir)
        if cp.state != STATE_HARVEST:
            raise PipelineError(f"nothing to harvest: run is at {cp.current_step} ({cp.state}); "
                                "harvest runs only after the plan is accepted.")
        plan_text = (run_dir / OUTPUT_FILE["s0_plan"]).read_text(encoding="utf-8")

    from .vendor.models import strip_markdown_json
    plan = json.loads(strip_markdown_json(plan_text))
    harvester = Harvester(cache_dir=run_dir / "api_cache", openalex_email=cp.openalex_email)
    result = harvester.harvest([q.strip() for q in plan["queries"] if q.strip()],
                               cp.target_citations)

    with run_lock(run_dir):
        cp = load_checkpoint(run_dir)
        if cp.state != STATE_HARVEST:  # a concurrent harvest already advanced the run
            return {"step_id": "s1_harvest", "report": cp.harvest, "next": _serve(cp, run_dir)}
        (run_dir / "citations_raw.json").write_text(json.dumps(result["citations"], indent=2),
                                                    encoding="utf-8")
        (run_dir / "harvest_report.json").write_text(json.dumps(result["report"], indent=2),
                                                     encoding="utf-8")
        cp.harvest = result["report"]
        cp.artifacts.update({"citations_raw": "citations_raw.json",
                             "harvest_report": "harvest_report.json"})
        facts = {k: result["report"][k] for k in ("accepted", "tier")}
        try:
            next_id = _route_after_harvest(cp)
        except PipelineError as exc:
            _fail(cp, "s1_harvest", [str(exc)])
            nxt = _serve(cp, run_dir)
        else:
            cp.record("s1_harvest", "completed", **facts)
            nxt = _advance(cp, run_dir, next_id)
        save_checkpoint(cp, run_dir)
    return {"step_id": "s1_harvest", "report": result["report"], "next": nxt}


def submit(runs_root: Path, run_id: str, step_token: str, content_path: str) -> dict[str, Any]:
    run_dir = _resolve_run_dir(runs_root, run_id)
    with run_lock(run_dir):
        cp = load_checkpoint(run_dir)
        step_id = cp.current_step
        if cp.state == STATE_HARVEST:
            return {"accepted": False, "step_id": step_id,
                    "errors": [f"run is waiting for the harvest; run `pipeline.py harvest "
                               f"{run_id}` first."]}
        if cp.state != STATE_AWAITING:
            return {"accepted": False, "step_id": step_id,
                    "errors": [f"run is {cp.state}; nothing to submit."]}
        if step_token != cp.step_token:
            return {"accepted": False, "step_id": step_id,
                    "errors": [f"stale_token: current step is {step_id}; use the token "
                               "from the most recent next/submit."],
                    "step_token": cp.step_token}

        src = Path(content_path).expanduser()
        if not src.is_file() or src.stat().st_size == 0:
            return {"accepted": False, "step_id": step_id,
                    "errors": [f"content_path {content_path!r} missing or empty."],
                    "step_token": cp.step_token}
        content = src.read_text(encoding="utf-8")

        errors = _validate(cp, run_dir, step_id, content)
        if errors:
            cp.attempts[step_id] = cp.attempts.get(step_id, 0) + 1
            attempts_left = MAX_ATTEMPTS[step_id] - cp.attempts[step_id]
            cp.record(step_id, "rejected", errors=errors)
            if attempts_left > 0:
                cp.arm_dispatch(step_id, DISPATCH_WORKER[step_id])  # rotate token
                save_checkpoint(cp, run_dir)
                return {"accepted": False, "step_id": step_id, "errors": errors,
                        "attempts_left": attempts_left, "step_token": cp.step_token,
                        "guidance": "Fix exactly the listed problems in the PREVIOUS output "
                                    "and resubmit the SAME step."}
            tier = (cp.harvest or {}).get("tier")
            if step_id == "s2_scout" and tier not in (None, TIER_FAILED):
                # Scout is a pressure valve: proceed if the harvest is already >= MINIMAL.
                cp.record(step_id, "exhausted_proceeding", tier=tier)
                note = f"scout exhausted; proceeding at tier {tier}"
                nxt = _advance(cp, run_dir, "s4_read")
            elif step_id in DEGRADABLE:
                cp.degraded.append(step_id)
                cp.record(step_id, "degraded")
                note = f"{step_id} exhausted its attempts; skipped and recorded as degraded"
                nxt = _advance(cp, run_dir, NEXT_AFTER_ACCEPT[step_id])
            else:
                _fail(cp, step_id, errors)
                note = f"{step_id} exhausted its attempts; run failed"
                nxt = _serve(cp, run_dir)
            save_checkpoint(cp, run_dir)
            return {"accepted": False, "step_id": step_id, "errors": errors,
                    "attempts_left": 0, "note": note, "next": nxt}

        canonical = run_dir / OUTPUT_FILE[step_id]
        if src.resolve() != canonical.resolve():
            shutil.copyfile(src, canonical)
        cp.artifacts[ARTIFACT_KEY[step_id]] = OUTPUT_FILE[step_id]
        cp.record(step_id, "accepted", attempts=cp.attempts.get(step_id, 0) + 1)
        nxt = _advance(cp, run_dir, NEXT_AFTER_ACCEPT[step_id])
        save_checkpoint(cp, run_dir)
    return {"accepted": True, "step_id": step_id, "next": nxt}


def status(runs_root: Path, run_id: str, full_history: bool = False) -> dict[str, Any]:
    run_dir = _resolve_run_dir(runs_root, run_id)
    cp = load_checkpoint(run_dir)
    return {
        "run_id": cp.run_id,
        "topic": cp.topic,
        "state": cp.state,
        "current_step": cp.current_step,
        "designated_worker": cp.designated_worker,
        "attempts": cp.attempts,
        "harvest": cp.harvest,
        "web_scout": cp.web_scout,
        "degraded": cp.degraded,
        "artifacts": {k: str(run_dir / v) for k, v in cp.artifacts.items()},
        "history": cp.history if full_history else cp.history[-20:],
        "failure": cp.failure,
    }
