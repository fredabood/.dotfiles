"""Paragraph-aware truncation for worker input corpora.

Lean replacement for upstream ``smart_truncate``: our corpus is markdown we
generate ourselves (never a JSON array), so the JSON binary-search branch is
dead weight — cut at the last paragraph boundary under the budget instead.
"""

from __future__ import annotations

TRUNCATION_MARKER = "\n\n[... truncated for context budget ...]\n"


def truncate_paragraphs(text: str, max_chars: int = 32000) -> str:
    if len(text) <= max_chars:
        return text
    budget = max_chars - len(TRUNCATION_MARKER)
    cut = text.rfind("\n\n", 0, budget)
    if cut < budget // 2:  # no useful boundary — hard cut
        cut = budget
    return text[:cut].rstrip() + TRUNCATION_MARKER
