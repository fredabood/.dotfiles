"""State-machine walk tests with a stubbed harvester (offline)."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from pipeline_core import machine
from pipeline_core.harvest import TIER_EXCELLENT, TIER_FAILED
from .test_validators import GOOD_PLAN, SIGNAL_DOC, reader_doc

POOL = [
    {"title": f"Paper {i}", "authors": ["Smith", "Jones"], "year": 2021,
     "doi": f"10.1/x{i}", "url": f"https://doi.org/10.1/x{i}",
     "journal": "J", "api_source": "crossref", "query": "q"}
    for i in range(1, 11)
]

REVIEW_OK = "\n".join([
    "# Literature Review",
    "## Theme\nConvergence holds (Smith et al., 2021).",
    "## Cross-source synthesis\nAgreement across (Smith & Jones, 2021).",
    "## Coverage limits\nThin on industry.",
])


class StubHarvester:
    tier = TIER_EXCELLENT
    pool = POOL

    def __init__(self, cache_dir, openalex_email=None, **kw):
        Path(cache_dir).mkdir(parents=True, exist_ok=True)

    def harvest(self, queries, target):
        report = {"target": target, "accepted": len(self.pool), "tier": self.tier,
                  "per_query": {q: 1 for q in queries}, "weak_queries": [],
                  "pool_cap": 2 * target}
        return {"citations": [dict(md) for md in self.pool], "report": report}


@pytest.fixture
def runs_root(tmp_path, monkeypatch):
    monkeypatch.setattr(machine, "Harvester", StubHarvester)
    StubHarvester.tier = TIER_EXCELLENT
    StubHarvester.pool = POOL
    return tmp_path / "runs"


def submit(runs_root, run_id, token, tmp_path, name, content):
    p = tmp_path / name
    p.write_text(content, encoding="utf-8")
    return machine.submit(runs_root, run_id, token, str(p))


def to_harvest(runs_root, tmp_path, plan=GOOD_PLAN, **start_kw):
    """start → accepted plan → harvest; returns (started, next-after-harvest)."""
    started = machine.start(runs_root, "CRDTs for offline-first apps", target_citations=5,
                            **start_kw)
    res = submit(runs_root, started["run_id"], started["next"]["step_token"], tmp_path,
                 "plan.json", plan)
    assert res["accepted"] is True
    assert res["next"]["kind"] == "harvest"
    harvested = machine.harvest(runs_root, started["run_id"])
    return started, harvested["next"]


def test_happy_path_full_walk(runs_root, tmp_path):
    started = machine.start(runs_root, "CRDTs for offline-first apps", target_citations=5)
    run_id, out = started["run_id"], Path(started["out_dir"])
    nxt = started["next"]
    assert nxt["kind"] == "dispatch" and nxt["action"]["worker"] == "planner"
    assert nxt["step_token"].startswith("drt-")

    res = submit(runs_root, run_id, nxt["step_token"], tmp_path, "plan.json", GOOD_PLAN)
    assert res["accepted"] is True and res["next"]["kind"] == "harvest"
    assert run_id in res["next"]["command"]

    nxt = machine.harvest(runs_root, run_id)["next"]
    assert (out / "harvest_report.json").exists()
    assert nxt["action"]["worker"] == "reader"

    res = submit(runs_root, run_id, nxt["step_token"], tmp_path, "reader.md", reader_doc(5))
    assert res["accepted"] is True, res
    nxt = res["next"]
    assert nxt["action"]["worker"] == "review-writer"
    assert len(list((out / "papers").glob("paper_*.md"))) == 5

    res = submit(runs_root, run_id, nxt["step_token"], tmp_path, "review.md", REVIEW_OK)
    assert res["accepted"] is True, res
    nxt = res["next"]
    assert nxt["action"]["worker"] == "signal"

    res = submit(runs_root, run_id, nxt["step_token"], tmp_path, "signal.md", SIGNAL_DOC)
    assert res["accepted"] is True
    done = res["next"]
    assert done["kind"] == "done"
    assert done["manifest"]["degraded"] == []
    for key in ("review", "signal", "bibliography", "bibliography_md"):
        assert Path(done["manifest"]["artifacts"][key]).exists(), key

    bib = json.loads((out / "bibliography.json").read_text())
    ids = [c["id"] for c in bib["citations"]]
    assert ids == [f"cite_{i:03d}" for i in range(1, len(ids) + 1)]
    assert machine.status(runs_root, run_id)["state"] == "done"


def test_bibliography_covers_read_sources_with_their_read_depth(runs_root, tmp_path):
    _, nxt = to_harvest(runs_root, tmp_path)
    run_id = nxt["run_id"]
    res = submit(runs_root, run_id, nxt["step_token"], tmp_path, "reader.md",
                 reader_doc(5, sources=[9, 2, 5, 7, 3]))
    res = submit(runs_root, run_id, res["next"]["step_token"], tmp_path, "review.md", REVIEW_OK)
    res = submit(runs_root, run_id, res["next"]["step_token"], tmp_path, "signal.md", SIGNAL_DOC)
    out = Path(res["next"]["manifest"]["artifacts"]["bibliography"])
    bib = json.loads(out.read_text())
    assert sorted(c["title"] for c in bib["citations"]) == \
        ["Paper 2", "Paper 3", "Paper 5", "Paper 7", "Paper 9"]  # not rows 1, 4, 6, 8, 10
    assert {c["read_depth"] for c in bib["citations"]} == {"abstract"}


def test_harvest_is_its_own_command(runs_root, tmp_path):
    started = machine.start(runs_root, "topic", target_citations=5)
    run_id = started["run_id"]
    res = submit(runs_root, run_id, started["next"]["step_token"], tmp_path, "plan.json",
                 GOOD_PLAN)
    assert res["next"]["kind"] == "harvest"
    assert machine.next_step(runs_root, run_id)["kind"] == "harvest"  # idempotent, no work
    assert not (Path(started["out_dir"]) / "citations_raw.json").exists()

    blocked = submit(runs_root, run_id, "drt-anything", tmp_path, "x.md", "x")
    assert blocked["accepted"] is False and "harvest" in blocked["errors"][0]


def test_harvest_refused_outside_harvest_step(runs_root):
    started = machine.start(runs_root, "topic", target_citations=5)
    with pytest.raises(machine.PipelineError, match="harvest"):
        machine.harvest(runs_root, started["run_id"])


def test_harvested_abstracts_reach_the_reader(runs_root, tmp_path):
    StubHarvester.pool = [dict(POOL[0], abstract="Merges converge in 42% fewer rounds."),
                          *POOL[1:]]
    _, nxt = to_harvest(runs_root, tmp_path)
    text = nxt["action"]["task_text"]
    assert "Merges converge in 42% fewer rounds." in text
    first, second = text.split("#### #2.")[0], text.split("#### #2.")[1]
    assert "Evidence available: abstract" in first
    assert "Evidence available: metadata-only" in second


def test_auto_scout_ignores_the_word_industry_when_harvest_is_healthy(runs_root, tmp_path):
    plan = json.loads(GOOD_PLAN)
    plan["strategy"] = "Balance academic and industry sources."
    _, nxt = to_harvest(runs_root, tmp_path, plan=json.dumps(plan))
    assert nxt["action"]["worker"] == "reader"


def test_web_scout_always_routes_through_scout(runs_root, tmp_path):
    _, nxt = to_harvest(runs_root, tmp_path, web_scout="always")
    assert nxt["action"]["worker"] == "web-scout"


def test_rejection_rotates_token_and_feeds_errors(runs_root, tmp_path):
    started = machine.start(runs_root, "topic", target_citations=5)
    run_id, tok = started["run_id"], started["next"]["step_token"]
    res = submit(runs_root, run_id, tok, tmp_path, "bad.json", "not json at all")
    assert res["accepted"] is False
    assert res["attempts_left"] == 2
    assert "JSON" in res["errors"][0]
    assert res["step_token"] != tok  # rotated

    # stale token consumes no attempt
    res2 = submit(runs_root, run_id, tok, tmp_path, "bad2.json", GOOD_PLAN)
    assert res2["accepted"] is False and "stale_token" in res2["errors"][0]
    assert machine.status(runs_root, run_id)["attempts"] == {"s0_plan": 1}

    res3 = submit(runs_root, run_id, res["step_token"], tmp_path, "ok.json", GOOD_PLAN)
    assert res3["accepted"] is True


def test_plan_exhaustion_fails_run(runs_root, tmp_path):
    started = machine.start(runs_root, "topic", target_citations=5)
    run_id = started["run_id"]
    tok = started["next"]["step_token"]
    for expected_left in (2, 1, 0):
        res = submit(runs_root, run_id, tok, tmp_path, "bad.json", "nope")
        assert res["attempts_left"] == expected_left
        tok = res.get("step_token")
    assert res["next"]["kind"] == "failed"
    assert machine.status(runs_root, run_id)["state"] == "failed"


def test_review_exhaustion_degrades_instead_of_failing(runs_root, tmp_path):
    _, nxt = to_harvest(runs_root, tmp_path)
    run_id = nxt["run_id"]
    res = submit(runs_root, run_id, nxt["step_token"], tmp_path, "reader.md", reader_doc(5))
    tok = res["next"]["step_token"]
    for _ in range(3):
        res = submit(runs_root, run_id, tok, tmp_path, "review.md", "no headings, no citations")
        tok = res.get("step_token")
    assert res["attempts_left"] == 0
    assert res["next"]["action"]["worker"] == "signal"

    res = submit(runs_root, run_id, res["next"]["step_token"], tmp_path, "signal.md", SIGNAL_DOC)
    manifest = res["next"]["manifest"]
    assert manifest["degraded"] == ["s6_review"]
    assert "review" not in manifest["artifacts"]


def test_biblio_recorded_once_in_history(runs_root, tmp_path):
    _, nxt = to_harvest(runs_root, tmp_path)
    run_id = nxt["run_id"]
    res = submit(runs_root, run_id, nxt["step_token"], tmp_path, "reader.md", reader_doc(5))
    res = submit(runs_root, run_id, res["next"]["step_token"], tmp_path, "review.md", REVIEW_OK)
    submit(runs_root, run_id, res["next"]["step_token"], tmp_path, "signal.md", SIGNAL_DOC)
    history = machine.status(runs_root, run_id, full_history=True)["history"]
    biblio = [h for h in history if h["step"] == "s8_biblio"]
    assert len(biblio) == 1 and biblio[0]["citations"] == 5


def test_deficit_routes_through_scout_and_merge(runs_root, tmp_path):
    StubHarvester.tier = TIER_FAILED
    StubHarvester.pool = POOL[:2]
    started, nxt = to_harvest(runs_root, tmp_path)
    assert nxt["action"]["worker"] == "web-scout"

    findings = "\n".join(
        ["## Query: CRDTs for offline-first apps"] +
        [f"- Src {i} | Pub | 2023 | https://ex.com/{i}" for i in range(4)] +
        ["## Coverage", "done"])
    res = submit(runs_root, started["run_id"], nxt["step_token"], tmp_path, "scout.md", findings)
    assert res["accepted"] is True
    # 2 academic + 4 web = 6 >= 5 → EXCELLENT tier now, reader next
    assert res["next"]["action"]["worker"] == "reader"
    report = json.loads((Path(started["out_dir"]) / "harvest_report.json").read_text())
    assert report["accepted"] == 6 and report["scout_added"] == 4


def test_dispatch_writes_the_brief_to_a_file(runs_root):
    started = machine.start(runs_root, "topic", target_citations=5)
    nxt = started["next"]
    brief = Path(nxt["brief_path"])
    assert brief.parent == Path(started["out_dir"]) / "briefs"
    assert brief.read_text(encoding="utf-8") == nxt["action"]["task_text"]


def test_next_step_idempotent(runs_root):
    started = machine.start(runs_root, "topic", target_citations=5)
    run_id, tok = started["run_id"], started["next"]["step_token"]
    again = machine.next_step(runs_root, run_id)
    assert again["step_token"] == tok and again["step_id"] == "s0_plan"


def test_out_dir_must_live_under_runs_root(tmp_path, monkeypatch):
    monkeypatch.setattr(machine, "Harvester", StubHarvester)
    with pytest.raises(machine.PipelineError, match="runs_root"):
        machine.start(tmp_path / "runs", "topic", 5, out_dir=str(tmp_path / "elsewhere"))
