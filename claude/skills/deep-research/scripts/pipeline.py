#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["pydantic>=2", "requests>=2.31"]
# ///
"""deep-research pipeline CLI. Every command prints one JSON object on stdout.

    uv run pipeline.py start --topic "..." [--target 25] [--web-scout auto|always|never]
    uv run pipeline.py next    <run_id>
    uv run pipeline.py harvest <run_id>                       # slow: run in the background
    uv run pipeline.py submit  <run_id> <step_token> <path>
    uv run pipeline.py status  <run_id> [--full-history]

Runs live under $DEEP_RESEARCH_RUNS_ROOT (default ~/.local/share/deep-research/runs).
Exit status: 0 ok, 1 pipeline error (JSON {"error": ...}), 2 usage error.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from pipeline_core import machine  # noqa: E402
from pipeline_core.paths import runs_root  # noqa: E402


def _parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="pipeline.py", description=__doc__.split("\n\n")[0])
    sub = p.add_subparsers(dest="command", required=True)

    s = sub.add_parser("start", help="create a run and return the planner dispatch")
    s.add_argument("--topic", required=True)
    s.add_argument("--target", type=int, default=25, help="target source count")
    s.add_argument("--web-scout", choices=machine.WEB_SCOUT_MODES, default="auto")
    s.add_argument("--openalex-email", default=os.environ.get("OPENALEX_EMAIL"),
                   help="mailto for the Crossref/OpenAlex polite pools")

    for name, help_text in (("next", "re-serve the current step (idempotent)"),
                            ("harvest", "run the citation harvest (slow)")):
        c = sub.add_parser(name, help=help_text)
        c.add_argument("run_id")

    sm = sub.add_parser("submit", help="validate a worker's output and advance")
    sm.add_argument("run_id")
    sm.add_argument("step_token")
    sm.add_argument("content_path")

    st = sub.add_parser("status", help="inspect a run")
    st.add_argument("run_id")
    st.add_argument("--full-history", action="store_true")
    return p


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    logging.basicConfig(level=logging.WARNING, stream=sys.stderr)
    root = runs_root()
    try:
        if args.command == "start":
            out = machine.start(root, args.topic, target_citations=args.target,
                                openalex_email=args.openalex_email, web_scout=args.web_scout)
        elif args.command == "next":
            out = machine.next_step(root, args.run_id)
        elif args.command == "harvest":
            out = machine.harvest(root, args.run_id)
        elif args.command == "submit":
            out = machine.submit(root, args.run_id, args.step_token, args.content_path)
        else:
            out = machine.status(root, args.run_id, full_history=args.full_history)
    except machine.PipelineError as exc:
        print(json.dumps({"error": str(exc)}))
        return 1
    print(json.dumps(out, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
