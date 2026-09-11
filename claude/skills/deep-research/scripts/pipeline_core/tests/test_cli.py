"""The pipeline.py CLI: JSON on stdout, runs root from the environment (offline)."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

CLI = Path(__file__).resolve().parents[2] / "pipeline.py"


def run(*args, runs_root):
    env = {**os.environ, "DEEP_RESEARCH_RUNS_ROOT": str(runs_root)}
    proc = subprocess.run([sys.executable, str(CLI), *args], capture_output=True, text=True,
                          env=env, timeout=60)
    return proc.returncode, json.loads(proc.stdout)


def test_start_next_status_round_trip(tmp_path):
    code, started = run("start", "--topic", "CRDTs", "--target", "10", runs_root=tmp_path)
    assert code == 0
    assert Path(started["out_dir"]).parent == tmp_path
    assert started["next"]["action"]["worker"] == "planner"

    code, nxt = run("next", started["run_id"], runs_root=tmp_path)
    assert code == 0 and nxt["step_token"] == started["next"]["step_token"]

    code, st = run("status", started["run_id"], runs_root=tmp_path)
    assert code == 0 and st["current_step"] == "s0_plan"


def test_errors_are_json_with_nonzero_exit(tmp_path):
    code, out = run("status", "dr-does-not-exist", runs_root=tmp_path)
    assert code == 1 and "unknown run_id" in out["error"]
