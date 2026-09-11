"""Worker prompts.

Prompts live beside this module (``prompts/``) and are read ``__file__``-relative,
so the CLI works from any working directory. Each file is a complete brief for
one worker: its role, its rules, and the exact output contract its validator
enforces. Variable content is substituted with ``str.replace`` on ``{name}``
placeholders — the files contain literal JSON braces, so ``str.format`` is unusable.
"""

from __future__ import annotations

from pathlib import Path

_PROMPTS = Path(__file__).parent / "prompts"


def _render(name: str, **values: object) -> str:
    text = (_PROMPTS / name).read_text(encoding="utf-8")
    for key, value in values.items():
        text = text.replace("{" + key + "}", str(value))
    return text


def planner_prompt(topic: str, target_citations: int) -> str:
    return _render("planner.md", topic=topic, target_citations=target_citations)


def scout_prompt(topic: str, queries: list[str], deficit: int, accepted: int, target: int) -> str:
    return _render("scout.md", topic=topic, deficit=deficit, accepted=accepted, target=target,
                   queries="\n".join(f"- {q}" for q in queries))


def reader_prompt(topic: str, corpus: str) -> str:
    return _render("reader.md", topic=topic, corpus=corpus)


def review_prompt(topic: str, outline: str, context: str, papers: str) -> str:
    return _render("review.md", topic=topic, outline=outline or "(none given)", context=context,
                   papers=papers)


def signal_prompt(topic: str, papers: str, review: str) -> str:
    review_block = review.strip() or "(The review step degraded; work from the notes alone.)"
    return _render("signal.md", topic=topic, papers=papers, review=review_block)
