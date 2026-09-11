import json
import sys
from pathlib import Path

import pytest

# Make `pipeline_core` importable when pytest runs from anywhere.
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

FIXTURES = Path(__file__).parent / "fixtures"


@pytest.fixture
def load_fixture():
    def _load(name: str):
        return json.loads((FIXTURES / name).read_text(encoding="utf-8"))

    return _load
