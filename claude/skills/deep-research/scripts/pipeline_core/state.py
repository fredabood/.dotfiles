"""Checkpoint state for the deep-research pipeline.

The checkpoint is the program counter. Writes are atomic (tmp + rename) under
an fcntl lock, so a concurrent reader (status, a second terminal) never sees a
torn file and two commands cannot interleave a read-modify-write cycle.
"""

from __future__ import annotations

import fcntl
import json
import secrets
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

from pydantic import BaseModel, Field

STATE_AWAITING = "awaiting_dispatch"
STATE_HARVEST = "awaiting_harvest"
STATE_DONE = "done"
STATE_FAILED = "failed"


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def mint_token() -> str:
    """Step token: drt-<32 hex>. Rotated on every (re-)dispatch so a stale
    submission can never be accepted for a newer attempt."""
    return "drt-" + secrets.token_hex(16)


class Checkpoint(BaseModel):
    version: int = 2
    run_id: str
    topic: str
    target_citations: int
    out_dir: str
    created_at: str = Field(default_factory=now_iso)
    updated_at: str = Field(default_factory=now_iso)

    current_step: str = "s0_plan"
    state: str = STATE_AWAITING  # awaiting_dispatch | awaiting_harvest | advancing | done | failed
    step_token: Optional[str] = None
    designated_worker: Optional[str] = None

    attempts: dict[str, int] = Field(default_factory=dict)
    history: list[dict[str, Any]] = Field(default_factory=list)
    artifacts: dict[str, str] = Field(default_factory=dict)
    harvest: Optional[dict[str, Any]] = None
    failure: Optional[dict[str, Any]] = None
    openalex_email: Optional[str] = None
    web_scout: str = "auto"  # auto | always | never
    degraded: list[str] = Field(default_factory=list)
    read_sources: dict[str, str] = Field(default_factory=dict)  # harvest row -> read depth

    # -- transitions -------------------------------------------------------

    def arm_dispatch(self, step_id: str, worker: str) -> None:
        """Enter (or re-enter after rejection) a worker step with a fresh token."""
        self.current_step = step_id
        self.state = STATE_AWAITING
        self.step_token = mint_token()
        self.designated_worker = worker

    def await_harvest(self) -> None:
        self.current_step = "s1_harvest"
        self.state = STATE_HARVEST
        self.step_token = None
        self.designated_worker = None

    def record(self, step_id: str, outcome: str, **extra: Any) -> None:
        self.history.append({"step": step_id, "outcome": outcome, "at": now_iso(), **extra})

    def finish(self, state: str, failure: Optional[dict] = None) -> None:
        self.state = state
        self.step_token = None
        self.designated_worker = None
        self.failure = failure


def run_dir_for(runs_root: Path, run_id: str) -> Path:
    return runs_root / run_id


def checkpoint_path(run_dir: Path) -> Path:
    return run_dir / "checkpoint.json"


@contextmanager
def run_lock(run_dir: Path):
    """Serialize read-modify-write cycles across tool subprocesses."""
    lock_file = run_dir / ".lock"
    run_dir.mkdir(parents=True, exist_ok=True)
    with open(lock_file, "w", encoding="utf-8") as fh:
        fcntl.flock(fh, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(fh, fcntl.LOCK_UN)


def load_checkpoint(run_dir: Path) -> Checkpoint:
    return Checkpoint.model_validate_json(checkpoint_path(run_dir).read_text(encoding="utf-8"))


def save_checkpoint(cp: Checkpoint, run_dir: Path) -> None:
    cp.updated_at = now_iso()
    tmp = checkpoint_path(run_dir).with_suffix(".json.tmp")
    tmp.write_text(cp.model_dump_json(indent=2), encoding="utf-8")
    tmp.rename(checkpoint_path(run_dir))
