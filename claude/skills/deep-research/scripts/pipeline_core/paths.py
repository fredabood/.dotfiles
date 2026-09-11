"""Where runs live.

``DEEP_RESEARCH_RUNS_ROOT`` overrides the default. Each run is one directory
holding its checkpoint, API cache and every artifact it produces.
"""

import os
from pathlib import Path

DEFAULT_RUNS_ROOT = Path("~/.local/share/deep-research/runs")


def runs_root() -> Path:
    return Path(os.environ.get("DEEP_RESEARCH_RUNS_ROOT") or DEFAULT_RUNS_ROOT).expanduser()
