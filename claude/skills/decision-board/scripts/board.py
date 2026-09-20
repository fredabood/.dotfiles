#!/usr/bin/env python3
"""Decision boards — many interlocking decisions, answered asynchronously, hosted in
the work app and frozen into the repo they decide.

A board has two lives, and which one it is in decides where the truth is:

    OPEN     the app's database is the truth. You answer the board in the work app.
             Nothing is on disk yet, and nothing needs to be.
    FROZEN   `freeze` pulls the app's canonical export, writes it into the deciding
             repo and commits it. From that moment the committed files are the
             record, and they are what every harvested issue permalinks to.
    DRIFTED  the app moved on after a freeze. `harvest-apply` refuses until you
             freeze again, because the committed record no longer says what the
             board says.

A frozen export is a directory, conventionally
<repo>/docs/decision-boards/<YYYY-MM-DD>-<slug>/:

    agenda.json   the cards
    answers.json  one entry per answered card
    harvest.json  which card landed where, at which answer hash
    BOARD.md      generated, GitHub-readable view

and the parent directory carries a generated README.md index.

A board is a collection instrument, never the archive: harvested decisions live in
issues and ADRs. Nothing here talks to claude.ai. Schema and states:
../references/schema.md.

Usage:
    board.py new --from <agenda.json>
    board.py revise <repo>/<board-id> --from <agenda.json> [--bump IDS] [--keep-answer IDS]
    board.py freeze <repo>/<board-id> [--into DIR] [--no-commit | --record SHA]
    board.py mark-harvested <repo>/<board-id> --cards IDS --target <owner/repo#N | vault:path.md> [--into DIR]

    board.py validate <dir>                       # these read a frozen export and
    board.py render <dir> [--check]               # need no network, which is what
    board.py index <root> [--check]               # keeps a board readable when the
    board.py harvest-plan <dir> [--format json|text]      # app is unreachable
    board.py harvest-apply <dir> --drafts <drafts.json> [--dry-run | --execute] [--out DIR]

`serve` was retired: it was a second writer of a board, and only one of the two
renderings you could see was writable (fredabood/.dotfiles#15).

Environment (this repo is public, so neither has a default here):
    DECISION_BOARD_API          the app's /api base; falls back to the
                                `- **Decision board API**:` line in
                                $MEMORY_VAULT_PATH/personal/profile.md
    JIRA_GRAPH_SERVICE_TOKEN    op://Homelab/Jira Graph Service Token/credential

Exit codes: 0 ok, 1 validation or check failure, 2 usage error.
Standard library only; runs on the macOS system python3 (3.9).
"""
import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

AGENDA_SCHEMA = "decision-board/1"
ANSWERS_SCHEMA = "decision-board-answers/1"
HARVEST_SCHEMA = "decision-board-harvest/1"

AGENDA_FILE = "agenda.json"
ANSWERS_FILE = "answers.json"
HARVEST_FILE = "harvest.json"
BOARD_FILE = "BOARD.md"
INDEX_FILE = "README.md"

RESOLUTION = "@resolution"
STATES = ("untouched", "decided", "flagged", "stale", "retired", "harvested", "changed-since-harvest")
BOARD_STATUSES = ("open", "harvested", "closed")

BOARD_ID_RE = re.compile(r"^\d{4}-\d{2}-\d{2}-[a-z0-9]+(?:-[a-z0-9]+)*$")
SECTION_ID_RE = re.compile(r"^[A-Z]{1,3}$")
CARD_ID_RE = re.compile(r"^[A-Z]{1,3}[0-9]{1,3}$")
OPTION_KEY_RE = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,38}[a-z0-9])?$")
REPO_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
TARGET_RE = re.compile(r"^(?:[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#\d+|vault:[A-Za-z0-9_./-]+\.md)$")
HTML_RE = re.compile(r"<[A-Za-z!/?]")

LIMITS = {
    "title": 120, "intro": 4000, "section_title": 80, "blurb": 600, "q": 200, "decides": 400,
    "option_title": 120, "detail": 600, "note": 4000, "resolution": 2000,
}

# Deliberately broad: a board is shared, versioned text and must never carry a credential.
SECRET_PATTERNS = [
    ("1Password reference", re.compile(r"op://")),
    ("private key", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("AWS access key", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("GitHub token", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}")),
    ("Slack token", re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}")),
    ("API key", re.compile(r"\bsk-[A-Za-z0-9_-]{20,}")),
    ("credential assignment", re.compile(
        r"(?i)\b(?:api[_-]?key|secret|token|passwd|password)\s*[:=]\s*['\"]?[A-Za-z0-9_\-/+=.]{12,}")),
]


class BoardError(Exception):
    """A problem the user must fix; printed without a traceback, exit 1."""


# --------------------------------------------------------------------------- files

def dump_json(obj):
    return json.dumps(obj, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def atomic_write(path, text):
    path = Path(path)
    fd, tmp = tempfile.mkstemp(prefix="." + path.name + ".", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.replace(tmp, str(path))
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def read_json(path):
    path = Path(path)
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except FileNotFoundError:
        raise BoardError("%s: missing" % path)
    except json.JSONDecodeError as exc:
        raise BoardError("%s: invalid JSON at line %d column %d: %s" % (path, exc.lineno, exc.colno, exc.msg))


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def empty_answers():
    return {"schema": ANSWERS_SCHEMA, "cards": {}}


def empty_harvest():
    return {"schema": HARVEST_SCHEMA, "cards": {}}


def split_ids(value):
    if not value:
        return []
    return [part.strip() for part in value.split(",") if part.strip()]


# --------------------------------------------------------------------------- validation

class Report:
    def __init__(self):
        self.errors = []
        self.warnings = []

    def err(self, where, msg):
        self.errors.append("%s: %s" % (where, msg))

    def warn(self, where, msg):
        self.warnings.append("%s: %s" % (where, msg))


def _text(rep, where, value, limit, required=True, allow_html=False):
    if value is None and not required:
        return
    if not isinstance(value, str) or (required and not value.strip()):
        rep.err(where, "must be a non-empty string")
        return
    if len(value) > limit:
        rep.err(where, "is %d characters (limit %d)" % (len(value), limit))
    if not allow_html and HTML_RE.search(value):
        rep.err(where, "contains HTML or a tag-like '<'; boards carry plain text only")
    _secrets(rep, where, value)


def _secrets(rep, where, value):
    for label, pattern in SECRET_PATTERNS:
        if pattern.search(value):
            rep.err(where, "looks like it contains a secret (%s); boards must never carry credentials" % label)


def _keys(rep, where, obj, allowed, required):
    for key in required:
        if key not in obj:
            rep.err(where, "missing field '%s'" % key)
    for key in obj:
        if key not in allowed:
            rep.err(where, "unknown field '%s'" % key)


def normalize_agenda(agenda):
    """Fill defaulted fields so the stored agenda is explicit. Mutates and returns it."""
    for section in agenda.get("sections") or []:
        for card in section.get("cards") or []:
            if isinstance(card, dict):
                card.setdefault("rev", 1)
                card.setdefault("retired", False)
                for opt in card.get("options") or []:
                    if isinstance(opt, dict):
                        opt.setdefault("recommended", False)
    return agenda


def validate_agenda(agenda, rep=None):
    rep = rep or Report()
    where = AGENDA_FILE
    if not isinstance(agenda, dict):
        rep.err(where, "top level must be an object")
        return rep
    _keys(rep, where, agenda, {"schema", "id", "title", "repo", "created", "status", "intro", "sections"},
          {"schema", "id", "title", "repo", "created", "status", "sections"})
    if agenda.get("schema") != AGENDA_SCHEMA:
        rep.err(where, "schema must be '%s'" % AGENDA_SCHEMA)
    if not (isinstance(agenda.get("id"), str) and BOARD_ID_RE.match(agenda["id"]) and len(agenda["id"]) <= 80):
        rep.err(where + ".id", "must look like YYYY-MM-DD-slug (lowercase, hyphens)")
    _text(rep, where + ".title", agenda.get("title"), LIMITS["title"])
    if not (isinstance(agenda.get("repo"), str) and REPO_RE.match(agenda["repo"])):
        rep.err(where + ".repo", "must be owner/name")
    if not (isinstance(agenda.get("created"), str) and DATE_RE.match(agenda["created"])):
        rep.err(where + ".created", "must be YYYY-MM-DD")
    if agenda.get("status") not in BOARD_STATUSES:
        rep.err(where + ".status", "must be one of %s" % ", ".join(BOARD_STATUSES))
    _text(rep, where + ".intro", agenda.get("intro"), LIMITS["intro"], required=False)

    sections = agenda.get("sections")
    if not isinstance(sections, list) or not sections:
        rep.err(where + ".sections", "must be a non-empty list")
        return rep
    seen_sections, seen_cards = set(), {}
    for si, section in enumerate(sections):
        sw = "%s.sections[%d]" % (where, si)
        if not isinstance(section, dict):
            rep.err(sw, "must be an object")
            continue
        _keys(rep, sw, section, {"id", "title", "blurb", "cards"}, {"id", "title", "cards"})
        sid = section.get("id")
        if not (isinstance(sid, str) and SECTION_ID_RE.match(sid)):
            rep.err(sw + ".id", "must be 1-3 uppercase letters")
        elif sid in seen_sections:
            rep.err(sw + ".id", "duplicate section id '%s'" % sid)
        seen_sections.add(sid)
        _text(rep, sw + ".title", section.get("title"), LIMITS["section_title"])
        _text(rep, sw + ".blurb", section.get("blurb"), LIMITS["blurb"], required=False)
        cards = section.get("cards")
        if not isinstance(cards, list) or not cards:
            rep.err(sw + ".cards", "must be a non-empty list")
            continue
        for ci, card in enumerate(cards):
            cw = "%s.cards[%d]" % (sw, ci)
            if not isinstance(card, dict):
                rep.err(cw, "must be an object")
                continue
            _validate_card(rep, cw, card, seen_cards)
    return rep


def _validate_card(rep, cw, card, seen_cards):
    _keys(rep, cw, card, {"id", "rev", "retired", "q", "decides", "options"}, {"id", "q", "decides", "options"})
    cid = card.get("id")
    if not (isinstance(cid, str) and CARD_ID_RE.match(cid)):
        rep.err(cw + ".id", "bad card id %r (1-3 uppercase letters then 1-3 digits, e.g. A1)" % (cid,))
    elif cid in seen_cards:
        rep.err(cw + ".id", "duplicate card id '%s' (also at %s)" % (cid, seen_cards[cid]))
    else:
        seen_cards[cid] = cw
    rev = card.get("rev", 1)
    if not (isinstance(rev, int) and not isinstance(rev, bool) and rev >= 1):
        rep.err(cw + ".rev", "must be an integer >= 1")
    if not isinstance(card.get("retired", False), bool):
        rep.err(cw + ".retired", "must be true or false")
    _text(rep, cw + ".q", card.get("q"), LIMITS["q"])
    _text(rep, cw + ".decides", card.get("decides"), LIMITS["decides"])
    options = card.get("options")
    if not isinstance(options, list):
        rep.err(cw + ".options", "must be a list")
        return
    if not 2 <= len(options) <= 4:
        rep.err(cw + ".options", "has %d options (need 2-4)" % len(options))
    keys, recommended = set(), 0
    for oi, opt in enumerate(options):
        ow = "%s.options[%d]" % (cw, oi)
        if not isinstance(opt, dict):
            rep.err(ow, "must be an object")
            continue
        _keys(rep, ow, opt, {"key", "title", "detail", "recommended"}, {"key", "title", "detail"})
        key = opt.get("key")
        if not (isinstance(key, str) and OPTION_KEY_RE.match(key)):
            rep.err(ow + ".key", "bad option key %r (lowercase letters, digits, hyphens; max 40)" % (key,))
        elif key in keys:
            rep.err(ow + ".key", "duplicate option key '%s'" % key)
        keys.add(key)
        _text(rep, ow + ".title", opt.get("title"), LIMITS["option_title"])
        _text(rep, ow + ".detail", opt.get("detail"), LIMITS["detail"])
        rec = opt.get("recommended", False)
        if not isinstance(rec, bool):
            rep.err(ow + ".recommended", "must be true or false")
        elif rec:
            recommended += 1
    if recommended > 1:
        rep.err(cw + ".options", "%d options marked recommended (at most 1)" % recommended)


def cards_by_id(agenda):
    out = {}
    for section in agenda.get("sections", []):
        for card in section.get("cards", []):
            out[card["id"]] = dict(card, section=section["id"])
    return out


ANSWER_FIELDS = {"choice", "note", "flagged", "rev", "at", "resolution"}


def validate_answer_entry(card, entry, where):
    """Validate one answer against its card. Returns a Report (shared by `validate` and `serve`)."""
    rep = Report()
    if not isinstance(entry, dict):
        rep.err(where, "must be an object")
        return rep
    _keys(rep, where, entry, ANSWER_FIELDS, {"choice", "flagged", "rev"})
    choice = entry.get("choice")
    keys = [o["key"] for o in card.get("options", [])]
    if choice is not None and not isinstance(choice, str):
        rep.err(where + ".choice", "must be an option key, null, or '%s'" % RESOLUTION)
    elif choice == RESOLUTION:
        _text(rep, where + ".resolution", entry.get("resolution"), LIMITS["resolution"])
    elif isinstance(choice, str) and choice not in keys:
        rep.warn(where + ".choice", "'%s' is not an option of %s; the answer is stale" % (choice, card["id"]))
    if choice != RESOLUTION and entry.get("resolution") is not None:
        rep.err(where + ".resolution", "only allowed when choice is '%s'" % RESOLUTION)
    if not isinstance(entry.get("flagged"), bool):
        rep.err(where + ".flagged", "must be true or false")
    rev = entry.get("rev")
    if not (isinstance(rev, int) and not isinstance(rev, bool) and rev >= 1):
        rep.err(where + ".rev", "must be an integer >= 1")
    elif rev > card.get("rev", 1):
        rep.err(where + ".rev", "is %d but card %s is only at rev %d" % (rev, card["id"], card.get("rev", 1)))
    if "note" in entry:
        _text(rep, where + ".note", entry["note"], LIMITS["note"], required=False, allow_html=True)
    if "at" in entry and not isinstance(entry["at"], str):
        rep.err(where + ".at", "must be an ISO timestamp string")
    return rep


def validate_answers(agenda, answers, rep=None):
    rep = rep or Report()
    where = ANSWERS_FILE
    if not isinstance(answers, dict):
        rep.err(where, "top level must be an object")
        return rep
    _keys(rep, where, answers, {"schema", "cards"}, {"schema", "cards"})
    if answers.get("schema") != ANSWERS_SCHEMA:
        rep.err(where, "schema must be '%s'" % ANSWERS_SCHEMA)
    cards = cards_by_id(agenda)
    entries = answers.get("cards")
    if not isinstance(entries, dict):
        rep.err(where + ".cards", "must be an object keyed by card id")
        return rep
    for cid, entry in sorted(entries.items()):
        cw = "%s.cards.%s" % (where, cid)
        if cid not in cards:
            rep.err(cw, "orphaned answer: card '%s' is not on the agenda (retire cards, never delete them)" % cid)
            continue
        sub = validate_answer_entry(cards[cid], entry, cw)
        rep.errors.extend(sub.errors)
        rep.warnings.extend(sub.warnings)
    return rep


def validate_harvest(agenda, harvest, rep=None):
    rep = rep or Report()
    where = HARVEST_FILE
    if not isinstance(harvest, dict) or harvest.get("schema") != HARVEST_SCHEMA or not isinstance(harvest.get("cards"), dict):
        rep.err(where, "must be {\"schema\": \"%s\", \"cards\": {...}}" % HARVEST_SCHEMA)
        return rep
    cards = cards_by_id(agenda)
    for cid, entry in sorted(harvest["cards"].items()):
        cw = "%s.cards.%s" % (where, cid)
        if cid not in cards:
            rep.err(cw, "orphaned harvest record: card '%s' is not on the agenda" % cid)
            continue
        if not isinstance(entry, dict):
            rep.err(cw, "must be an object")
            continue
        _keys(rep, cw, entry, {"target", "hash", "at"}, {"target", "hash"})
        if not (isinstance(entry.get("target"), str) and TARGET_RE.match(entry["target"])):
            rep.err(cw + ".target", "must be owner/repo#N or vault:path.md")
    return rep


# --------------------------------------------------------------------------- board model

class Board:
    def __init__(self, path, agenda, answers, harvest):
        self.path = Path(path)
        self.agenda = agenda
        self.answers = answers
        self.harvest = harvest

    @classmethod
    def load(cls, path, strict=True):
        path = Path(path)
        if not (path / AGENDA_FILE).is_file():
            raise BoardError("%s: not a decision board (no %s)" % (path, AGENDA_FILE))
        agenda = read_json(path / AGENDA_FILE)
        answers = read_json(path / ANSWERS_FILE) if (path / ANSWERS_FILE).exists() else empty_answers()
        harvest = read_json(path / HARVEST_FILE) if (path / HARVEST_FILE).exists() else empty_harvest()
        board = cls(path, agenda, answers, harvest)
        if strict:
            rep = board.validate()
            if rep.errors:
                raise BoardError("\n".join(["%s: board is invalid:" % path] + ["  " + e for e in rep.errors]))
        return board

    def validate(self):
        rep = validate_agenda(self.agenda)
        if rep.errors:
            return rep
        validate_answers(self.agenda, self.answers, rep)
        validate_harvest(self.agenda, self.harvest, rep)
        return rep

    @property
    def cards(self):
        return cards_by_id(self.agenda)

    def answer(self, cid):
        return self.answers.get("cards", {}).get(cid)

    def state(self, cid):
        return card_state(self.cards[cid], self.answer(cid), self.harvest.get("cards", {}).get(cid))

    def counts(self):
        counts = dict((s, 0) for s in STATES)
        for cid in self.cards:
            counts[self.state(cid)] += 1
        return counts


def answer_hash(entry):
    """Hash of what was decided. `at` is excluded so re-saving an unchanged answer changes nothing."""
    payload = {k: entry.get(k) for k in ("choice", "note", "flagged", "resolution", "rev")}
    payload["note"] = payload["note"] or ""
    return hashlib.sha256(json.dumps(payload, sort_keys=True, ensure_ascii=False).encode("utf-8")).hexdigest()[:16]


def card_state(card, entry, harvested):
    if card.get("retired"):
        return "retired"
    if not entry or (entry.get("choice") is None and not entry.get("flagged")):
        return "untouched"
    if entry.get("flagged"):
        return "flagged"
    keys = [o["key"] for o in card["options"]]
    if entry.get("rev", 1) < card.get("rev", 1) or (entry["choice"] != RESOLUTION and entry["choice"] not in keys):
        return "stale"
    if harvested:
        return "harvested" if harvested.get("hash") == answer_hash(entry) else "changed-since-harvest"
    return "decided"


# --------------------------------------------------------------------------- markdown

MD_SPECIAL = re.compile(r"([\\`*_\[\]<>|])")
MD_LINE_START = re.compile(r"^([#>+-]|\d+[.)])(?=\s|$)")
URL_RE = re.compile(r"https?://[^\s<>|`]+[^\s<>|`.,;:!?)\]]")
INLINE_SUBSET = re.compile(r"(\*\*[^*\n]+\*\*|`[^`\n]+`)")


def _escape_span(text):
    """Escape markdown in one span of text; bare URLs become <autolinks> so markdownlint MD034 passes."""
    out, pos = [], 0
    for m in URL_RE.finditer(text):
        out.append(MD_SPECIAL.sub(r"\\\1", text[pos:m.start()]))
        out.append("<%s>" % m.group(0))
        pos = m.end()
    out.append(MD_SPECIAL.sub(r"\\\1", text[pos:]))
    return "".join(out)


def _escape_line(line):
    line = _escape_span(line.strip())
    return MD_LINE_START.sub(lambda m: "\\" + m.group(1), line)


def md_flat(text):
    """A single-line field (title, question, option text): whitespace collapsed, markdown escaped."""
    return _escape_line(" ".join(str(text).split()))


def md_lines(text):
    """A multi-line field (note, resolution): line breaks kept, each line escaped."""
    return [_escape_line(line) for line in str(text).splitlines()] or [""]


def md_inline(text):
    """Escape, but keep the minimal markup subset boards allow in `intro`: **bold** and `code`."""
    out = []
    for part in INLINE_SUBSET.split(text):
        if INLINE_SUBSET.fullmatch(part):
            out.append(part)
        elif part:
            out.append(_escape_span(part))
    return MD_LINE_START.sub(lambda m: "\\" + m.group(1), "".join(out))


def md_paragraphs(text):
    paras = [p.strip() for p in re.split(r"\n\s*\n", text or "") if p.strip()]
    return [md_inline(" ".join(p.split())) for p in paras]


def md_quote(label, text):
    lines = md_lines(text)
    while len(lines) > 1 and not lines[-1]:
        lines.pop()
    out = ["> **%s:** %s" % (label, lines[0])]
    out += [">" if not line else "> " + line for line in lines[1:]]
    return out


def md_join(lines):
    text = "\n".join(line.rstrip() for line in lines)
    return re.sub(r"\n{3,}", "\n\n", text).strip("\n") + "\n"


def render_board(board):
    agenda, cards = board.agenda, board.cards
    counts = board.counts()
    total = len(cards)
    out = [
        "# %s" % md_flat(agenda["title"]),
        "",
        "<!-- decision-board: generated by board.py render. Edit agenda.json or answers.json, never this file. -->",
        "",
        "| Board | Repo | Created | Status |",
        "|---|---|---|---|",
        "| `%s` | %s | %s | %s |" % (agenda["id"], md_flat(agenda["repo"]), agenda["created"], agenda["status"]),
        "",
        "**Progress:** %s." % progress_phrase(counts, total),
        "",
    ]
    for para in md_paragraphs(agenda.get("intro")):
        out += [para, ""]
    out += ["| Section | Cards | Decided | Harvested | Flagged | Stale | Untouched |", "|---|---|---|---|---|---|---|"]
    for section in agenda["sections"]:
        sc = dict((s, 0) for s in STATES)
        for card in section["cards"]:
            sc[board.state(card["id"])] += 1
        out.append("| %s · %s | %d | %d | %d | %d | %d | %d |" % (
            section["id"], md_flat(section["title"]), len(section["cards"]), sc["decided"],
            sc["harvested"] + sc["changed-since-harvest"], sc["flagged"], sc["stale"], sc["untouched"]))
    out.append("")
    for section in agenda["sections"]:
        out += ["## %s · %s" % (section["id"], md_flat(section["title"])), ""]
        if section.get("blurb"):
            out += [md_flat(section["blurb"]), ""]
        for card in section["cards"]:
            out += render_card(board, card)
    return md_join(out)


def progress_phrase(counts, total):
    decided = counts["decided"] + counts["harvested"] + counts["changed-since-harvest"]
    parts = ["%d of %d decided" % (decided, total - counts["retired"])]
    for label, key in (("harvested", "harvested"), ("changed since harvest", "changed-since-harvest"),
                       ("flagged", "flagged"), ("stale", "stale"), ("retired", "retired")):
        if counts[key]:
            parts.append("%d %s" % (counts[key], label))
    return " · ".join(parts)


STATE_LABEL = {
    "untouched": "Not decided",
    "decided": "Decided",
    "flagged": "Needs discussion",
    "stale": "Stale — answered against an earlier wording; confirm or change",
    "retired": "Retired",
    "harvested": "Decided · harvested",
    "changed-since-harvest": "Decided · changed since harvest",
}


def render_card(board, card):
    cid = card["id"]
    entry = board.answer(cid) or {}
    state = board.state(cid)
    heading = "### %s · %s" % (cid, md_flat(card["q"]))
    if card.get("retired"):
        heading += " (retired)"
    out = [heading, "", "**Decides:** %s" % md_flat(card["decides"]), ""]
    for opt in card["options"]:
        box = "x" if entry.get("choice") == opt["key"] else " "
        rec = ", recommended" if opt.get("recommended") else ""
        out.append("- [%s] **%s** (`%s`%s) — %s" % (box, md_flat(opt["title"]), opt["key"], rec, md_flat(opt["detail"])))
    out.append("")
    status = "**Status:** %s" % STATE_LABEL[state]
    record = board.harvest.get("cards", {}).get(cid)
    if record and state in ("harvested", "changed-since-harvest"):
        status += " → %s" % md_flat(record["target"])
    if card.get("rev", 1) > 1:
        status += " · card rev %d" % card["rev"]
    out += [status, ""]
    if entry.get("choice") == RESOLUTION:
        out += md_quote("Resolved in discussion", entry.get("resolution", "")) + [""]
    elif entry.get("choice") and state == "stale":
        out += ["Previous answer: `%s` (rev %d)" % (entry["choice"], entry.get("rev", 1)), ""]
    if entry.get("note"):
        out += md_quote("Note", entry["note"]) + [""]
    return out


def render_index(root):
    root = Path(root)
    boards = []
    for child in sorted(p for p in root.iterdir() if p.is_dir() and (p / AGENDA_FILE).is_file()):
        boards.append(Board.load(child))
    out = [
        "# Decision boards",
        "",
        "<!-- decision-board: generated by board.py index. Do not edit by hand. -->",
        "",
        "Each board collects many interlocking decisions. The durable record is the issue or ADR a card "
        "was harvested into, listed in the last column. These files are a frozen export: boards are "
        "answered in the work app, and `board.py freeze` is what writes them here.",
        "",
    ]
    if not boards:
        out += ["No boards yet."]
        return md_join(out)
    out += ["| Board | Title | Created | Status | Progress | Harvested into |", "|---|---|---|---|---|---|"]
    for board in boards:
        agenda = board.agenda
        targets = sorted(set(r["target"] for r in board.harvest.get("cards", {}).values()))
        out.append("| [%s](%s/%s) | %s | %s | %s | %s | %s |" % (
            agenda["id"], board.path.name, BOARD_FILE, md_flat(agenda["title"]), agenda["created"],
            agenda["status"], progress_phrase(board.counts(), len(board.cards)),
            ", ".join(md_flat(t) for t in targets) or "—"))
    return md_join(out)


# --------------------------------------------------------------------------- commands

def write_generated(path, text, check):
    path = Path(path)
    current = path.read_text(encoding="utf-8") if path.exists() else None
    if check:
        if current != text:
            raise BoardError("%s is stale — run: board.py %s %s" % (
                path, "index" if path.name == INDEX_FILE else "render", path.parent))
        return False
    if current != text:
        atomic_write(path, text)
        return True
    return False


def cmd_validate(args):
    board = Board.load(args.dir, strict=False)
    rep = board.validate()
    for w in rep.warnings:
        print("warning: " + w)
    if rep.errors:
        for e in rep.errors:
            print("error: " + e)
        print("%s: %d error(s)" % (args.dir, len(rep.errors)))
        return 1
    counts = board.counts()
    print("%s: valid · %s" % (args.dir, progress_phrase(counts, len(board.cards))))
    return 0


def _card_content(card):
    """What makes a card "changed" for the purposes of a revision.

    Nothing in this file calls it any more — the refusal it feeds moved to the
    app with the rest of `revise` (work#527). It stays because it is the SOURCE
    the app vendors that comparison from, by AST, so the two cannot drift.
    """
    return {
        "q": card.get("q"),
        "decides": card.get("decides"),
        "options": [(o.get("key"), o.get("title"), o.get("detail"), bool(o.get("recommended"))) for o in card.get("options", [])],
    }


def cmd_revise(args):
    """Replace a board's agenda, in the app.

    The refusals live server-side now (work#527) — a card cannot be deleted, only
    retired; retirement is permanent; and a card that already has an ANSWER and
    whose question or options changed must be named in --bump or --keep-answer.
    Validating here first is still worth it: a malformed agenda fails against the
    file you are editing, with one message per problem, instead of one flattened
    400.
    """
    repo, board_id = board_ref(args.board)
    new = read_json(args.source)
    if isinstance(new, dict):
        normalize_agenda(new)
    rep = validate_agenda(new)
    if rep.errors:
        raise BoardError("\n".join(["%s: new agenda is invalid:" % args.source]
                                   + ["  " + e for e in rep.errors]))
    bump, keep = split_ids(args.bump), split_ids(args.keep_answer)
    out = api("POST", "/boards/%s/%s/revise" % (repo, board_id),
              {"agenda": new, "bump": bump, "keep": keep})
    for label, ids in (("bumped (answer now stale)", out.get("bumped") or []),
                       ("kept (answer still stands)", out.get("kept") or [])):
        if ids:
            print("%s: %s" % (label, ", ".join(ids)))
    states = (out.get("snapshot") or {}).get("states") or {}
    # Seed every state: progress_phrase indexes all of them, and a board with no
    # flagged card would otherwise KeyError on its own success message.
    counts = dict((st, 0) for st in STATES)
    for st in states.values():
        counts[st] = counts.get(st, 0) + 1
    print("%s/%s: revised · %s" % (repo, board_id, progress_phrase(counts, len(states))))
    print("a revision does not re-freeze; run `board.py freeze %s/%s` when you commit it"
          % (repo, board_id))
    return 0


def cmd_render(args):
    board = Board.load(args.dir)
    changed = write_generated(board.path / BOARD_FILE, render_board(board), args.check)
    print("%s: %s" % (board.path / BOARD_FILE, "up to date" if args.check or not changed else "written"))
    return 0


def cmd_index(args):
    root = Path(args.root)
    if not root.is_dir():
        raise BoardError("%s: not a directory" % root)
    changed = write_generated(root / INDEX_FILE, render_index(root), args.check)
    print("%s: %s" % (root / INDEX_FILE, "up to date" if args.check or not changed else "written"))
    return 0


def harvest_plan(board):
    cards, records = board.cards, board.harvest.get("cards", {})
    plan = {
        "board": board.agenda["id"], "repo": board.agenda["repo"], "path": str(board.path),
        "counts": board.counts(), "to_harvest": [], "to_update": [], "harvested": [],
        "open": {"flagged": [], "stale": [], "untouched": []}, "retired": [], "cards": [],
    }
    for section in board.agenda["sections"]:
        for card in section["cards"]:
            cid = card["id"]
            state = board.state(cid)
            entry = board.answer(cid) or {}
            opt = next((o for o in card["options"] if o["key"] == entry.get("choice")), None)
            item = {
                "id": cid, "section": section["id"], "state": state, "q": card["q"], "decides": card["decides"],
                "choice": entry.get("choice"), "choice_title": opt["title"] if opt else None,
                "resolution": entry.get("resolution"), "note": entry.get("note") or "",
                "hash": answer_hash(entry) if entry else None,
                "target": records.get(cid, {}).get("target"),
            }
            plan["cards"].append(item)
            if state == "decided":
                plan["to_harvest"].append(cid)
            elif state == "changed-since-harvest":
                plan["to_update"].append(cid)
            elif state == "harvested":
                plan["harvested"].append(cid)
            elif state == "retired":
                plan["retired"].append(cid)
            else:
                plan["open"][state].append(cid)
    return plan


def cmd_harvest_plan(args):
    plan = harvest_plan(Board.load(args.dir))
    if args.format == "json":
        sys.stdout.write(dump_json(plan))
        return 0
    print("%s · %d to harvest · %d to update · %d already harvested" % (
        plan["board"], len(plan["to_harvest"]), len(plan["to_update"]), len(plan["harvested"])))
    for label, ids in (("to harvest", plan["to_harvest"]), ("to update (changed since harvest)", plan["to_update"]),
                       ("open: needs discussion", plan["open"]["flagged"]), ("open: stale", plan["open"]["stale"]),
                       ("open: not decided", plan["open"]["untouched"])):
        if ids:
            print("  %s: %s" % (label, ", ".join(ids)))
    return 0


def cmd_mark_harvested(args):
    """Record where decided cards landed — in the app, then in the local export.

    Both, and in that order, because the two have different jobs. The app owns
    the harvest log: it is what makes a card read `harvested` rather than
    `decided` the next time anyone opens the board, and without it a completed
    harvest would be offered again. The export is what the committed record
    shows, and it is NOT refreshed by the drift check — `content_hash` covers the
    agenda and answers only, on purpose, so that marking a card harvested does
    not make a just-frozen board read as drifted. That deliberate blind spot is
    exactly why the local files have to be rewritten here instead of waiting for
    a drift banner that will never appear.
    """
    repo, board_id = board_ref(args.board)
    target = args.target
    if not TARGET_RE.match(target):
        raise BoardError("--target must be owner/repo#N or vault:path.md, got %r" % target)
    ids = split_ids(args.cards)
    if not ids:
        raise BoardError("--cards needs at least one card id")
    api("POST", "/boards/%s/%s/harvest" % (repo, board_id), {"cards": ids, "target": target})
    print("marked %s → %s" % (", ".join(ids), target))
    if args.into:
        refresh_export(repo, board_id, Path(args.into))
        print("refreshed %s — commit harvest.json and BOARD.md" % args.into)
    return 0


def refresh_export(repo, board_id, target):
    """Rewrite a frozen export's files from the app. Does not record a freeze."""
    export = api("GET", "/boards/%s/%s/export" % (repo, board_id))
    for name in (AGENDA_FILE, ANSWERS_FILE, HARVEST_FILE, BOARD_FILE):
        atomic_write(target / name, export["files"][name])
    if (target.parent / INDEX_FILE).exists():
        write_generated(target.parent / INDEX_FILE, render_index(target.parent), check=False)
    return export


# --------------------------------------------------------------------------- harvest-apply

DRAFTS_SCHEMA = "decision-board-drafts/1"
ROUTES = ("issue", "comment", "vault")
ISSUE_REF_RE = re.compile(r"^([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)#(\d+)$")
VAULT_PATH_RE = re.compile(r"^(?!/)(?!.*(?:^|/)\.\.(?:/|$))[A-Za-z0-9_./ -]+\.md$")
GITHUB_REMOTE_RE = re.compile(r"github\.com[:/]([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?/?$")
MARKER_RE = re.compile(r"<!-- decision-board: board=(\S+) cards=([A-Z0-9,]+) hash=([0-9a-f]+) -->")
# Repos whose hooks gate GitHub issue writes by inspecting the agent's own gh commands. A script that
# called gh itself would walk past those gates, so --execute is refused there.
GATED_HOOKS = (".claude/hooks/github-skill-gate.sh", ".claude/hooks/label-taxonomy-check.sh")


def marker_hash(cards, board):
    joined = ",".join("%s:%s" % (cid, answer_hash(board.answer(cid))) for cid in sorted(cards))
    return hashlib.sha256(joined.encode("utf-8")).hexdigest()[:16]


def draft_marker(board_id, cards, board):
    return "<!-- decision-board: board=%s cards=%s hash=%s -->" % (board_id, ",".join(sorted(cards)), marker_hash(cards, board))


def git_facts(path):
    """(repo_root, head_sha, path_in_repo, dirty) for a board directory, or None outside git."""
    import subprocess

    def git(*args):
        return subprocess.run(["git", "-C", str(path)] + list(args), capture_output=True, text=True, timeout=20)

    top = git("rev-parse", "--show-toplevel")
    if top.returncode != 0:
        return None
    root = Path(top.stdout.strip())
    head = git("rev-parse", "HEAD")
    # Only the inputs must be committed. harvest.json and the generated markdown are what a harvest
    # writes, so a rerun before committing them must still be allowed (and be a no-op).
    dirty = git("status", "--porcelain", "--", AGENDA_FILE, ANSWERS_FILE)
    remote = git("remote", "get-url", "origin")
    m = GITHUB_REMOTE_RE.search(remote.stdout.strip()) if remote.returncode == 0 else None
    return {
        "root": root,
        "sha": head.stdout.strip() if head.returncode == 0 else None,
        "rel": str(Path(path).resolve().relative_to(root.resolve())),
        "dirty": bool(dirty.stdout.strip()),
        # The repo that STORES the board. Usually the repo it decides (agenda "repo"), but not always:
        # a board carrying evidence the decided repo forbids lives with the repo that owns the evidence.
        "storage_repo": "%s/%s" % (m.group(1), m.group(2)) if m else None,
    }


def require_frozen(board, path):
    """Refuse to harvest unless this directory IS the app's frozen record.

    This replaces the old "commit your answers first" dirty-check, which asked a
    weaker question. A clean worktree only says nobody edited these files; it
    says nothing about whether they still match the board people are answering.
    Since the app became the truth for an open board, the committed files can be
    pristine AND months stale, and a harvested issue would quote a record that
    no longer reflects the decision.

    Three distinct refusals, because they need three different fixes:

      never frozen   -> `board.py freeze` (there is no commit to link to)
      app moved on   -> `board.py freeze` again (the app is ahead of the freeze)
      wrong files    -> this directory is not that export; re-run freeze --into here

    Returns the freeze sha, which is the commit every harvested item links to.
    """
    repo = repo_slug(board.agenda.get("repo") or "")
    board_id = board.agenda["id"]
    export = api("GET", "/boards/%s/%s/export" % (repo, board_id))
    if not export.get("frozen_sha"):
        raise BoardError(
            "%s/%s has never been frozen. Run `board.py freeze %s/%s --into %s` first — a harvested "
            "issue links to the committed record, and there is not one yet (or use --dry-run)."
            % (repo, board_id, repo, board_id, path))
    if export.get("drifted"):
        raise BoardError(
            "%s/%s has changed in the app since it was frozen. Re-run "
            "`board.py freeze %s/%s --into %s` so the harvest quotes what the board actually says "
            "(or use --dry-run)." % (repo, board_id, repo, board_id, path))
    local = dump_json(board.agenda) + dump_json(board.answers)
    if hashlib.sha256(local.encode("utf-8")).hexdigest()[:16] != export["content_hash"]:
        raise BoardError(
            "%s does not match the frozen export of %s/%s. Run "
            "`board.py freeze %s/%s --into %s` to refresh it (or use --dry-run)."
            % (path, repo, board_id, repo, board_id, path))
    return export["frozen_sha"]


def repo_slug(value):
    """`owner/name` -> `name`; the app keys a board by the bare repo name."""
    return (value or "").split("/")[-1]



def validate_drafts(board, drafts):
    """Check a drafts file against the board. Returns (errors, drafts list)."""
    errs = []
    if not isinstance(drafts, dict) or drafts.get("schema") != DRAFTS_SCHEMA or not isinstance(drafts.get("drafts"), list):
        return ["drafts file must be {\"schema\": \"%s\", \"drafts\": [...]}" % DRAFTS_SCHEMA], []
    seen = {}
    records = board.harvest.get("cards", {})
    for i, d in enumerate(drafts["drafts"]):
        where = "drafts[%d]" % i
        if not isinstance(d, dict):
            errs.append("%s: must be an object" % where)
            continue
        route = d.get("route")
        allowed = {"issue": {"route", "cards", "repo", "title", "body", "labels"},
                   "comment": {"route", "cards", "issue", "body"},
                   "vault": {"route", "cards", "path", "body"}}.get(route)
        if allowed is None:
            errs.append("%s.route: must be one of %s" % (where, ", ".join(ROUTES)))
            continue
        for key in set(d) - allowed:
            errs.append("%s: unknown field '%s' for route %s" % (where, key, route))
        cards = d.get("cards")
        if not isinstance(cards, list) or not cards or not all(isinstance(c, str) for c in cards):
            errs.append("%s.cards: must be a non-empty list of card ids" % where)
            continue
        body = d.get("body")
        if not isinstance(body, str) or not body.strip():
            errs.append("%s.body: must be a non-empty string" % where)
        else:
            if MARKER_RE.search(body):
                errs.append("%s.body: already contains a decision-board marker; harvest-apply adds it" % where)
            rep = Report()
            _secrets(rep, where + ".body", body)
            errs += rep.errors
        if route == "issue":
            if not (isinstance(d.get("repo"), str) and REPO_RE.match(d["repo"])):
                errs.append("%s.repo: must be owner/name" % where)
            if not (isinstance(d.get("title"), str) and 0 < len(d["title"].strip()) <= 200):
                errs.append("%s.title: must be 1-200 characters" % where)
            if "labels" in d and not (isinstance(d["labels"], list) and all(isinstance(x, str) and x for x in d["labels"])):
                errs.append("%s.labels: must be a list of label names" % where)
        elif route == "comment":
            if not (isinstance(d.get("issue"), str) and ISSUE_REF_RE.match(d["issue"])):
                errs.append("%s.issue: must be owner/repo#N" % where)
        elif route == "vault":
            if not (isinstance(d.get("path"), str) and VAULT_PATH_RE.match(d["path"])):
                errs.append("%s.path: must be a relative path ending in .md, with no '..'" % where)
        for cid in cards:
            if cid in seen:
                errs.append("%s: card %s is already in drafts[%d]" % (where, cid, seen[cid]))
                continue
            seen[cid] = i
            if cid not in board.cards:
                errs.append("%s: card %s is not on the board" % (where, cid))
                continue
            state = board.state(cid)
            if state == "harvested":
                continue  # reported and skipped at apply time: this is what makes a rerun a no-op
            if state == "changed-since-harvest":
                if route != "comment" or d.get("issue") != records[cid]["target"]:
                    errs.append("%s: card %s changed since it was harvested into %s; route it as a comment on "
                                "that issue, not a new target" % (where, cid, records[cid]["target"]))
            elif state != "decided":
                errs.append("%s: card %s is %s; only decided cards are harvested" % (where, cid, state))
    return errs, drafts["drafts"]


def cmd_harvest_apply(args):
    import shlex
    import subprocess

    board = Board.load(args.dir)
    errs, drafts = validate_drafts(board, read_json(args.drafts))
    if errs:
        raise BoardError("\n".join(["drafts refused:"] + ["  " + e for e in errs]))
    board_id = board.agenda["id"]
    facts = git_facts(board.path)
    freeze_sha = None
    if not args.dry_run:
        if facts is None:
            raise BoardError("%s is not inside a git repository; a board must be versioned before it is harvested" % board.path)
        freeze_sha = require_frozen(board, board.path)
    if args.execute:
        gated = [h for h in GATED_HOOKS if (facts["root"] / h).exists()]
        if gated:
            raise BoardError("refusing --execute: %s gates GitHub writes with %s. Run without --execute and "
                             "issue the printed gh commands yourself so those gates apply."
                             % (facts["root"], ", ".join(gated)))

    # The permalink points at the FREEZE commit, not at HEAD. HEAD moves; the
    # freeze is the commit whose bytes the app certified as this board's record,
    # which is what a harvested issue is claiming to quote.
    link = None
    sha = freeze_sha or (facts or {}).get("sha")
    if facts and sha:
        link = "https://github.com/%s/blob/%s/%s/%s" % (
            facts["storage_repo"] or board.agenda["repo"], sha, facts["rel"], BOARD_FILE)
    outdir = Path(args.out) if args.out else Path(tempfile.mkdtemp(prefix="decision-board-%s-" % board_id))
    outdir.mkdir(parents=True, exist_ok=True)

    def gh(*argv):
        res = subprocess.run(["gh"] + list(argv), capture_output=True, text=True, timeout=120)
        if res.returncode != 0:
            raise BoardError("gh %s failed: %s" % (" ".join(argv[:2]), (res.stderr or res.stdout).strip()))
        return res.stdout

    existing_cache = {}

    def markers_in(texts, ref):
        """This board's markers in some issue or comment bodies: [(ref, cards, hash)]."""
        found = []
        for text in texts:
            for m in MARKER_RE.finditer(text or ""):
                if m.group(1) == board_id:
                    found.append((ref, m.group(2).split(","), m.group(3)))
        return found

    def existing_markers(route, where):
        """Markers already on GitHub for this board: in issue bodies of a repo, or comments of an issue."""
        key = (route, where)
        if key not in existing_cache:
            if route == "issue":
                out = gh("issue", "list", "--repo", where, "--state", "all", "--limit", "200",
                         "--search", "\"%s\" in:body" % board_id, "--json", "number,body")
                existing_cache[key] = sum((markers_in([i.get("body")], "%s#%d" % (where, i["number"]))
                                           for i in json.loads(out or "[]")), [])
            else:
                repo, num = ISSUE_REF_RE.match(where).groups()
                out = gh("issue", "view", num, "--repo", repo, "--json", "comments")
                existing_cache[key] = markers_in([c.get("body") for c in json.loads(out or "{}").get("comments", [])], where)
        return existing_cache[key]

    def repair(route, where, live):
        """Record cards whose current answer is already on GitHub; return the cards still to write.

        Only a marker whose hash matches the current answers counts: an issue made for an older answer
        is not this decision, and the card needs an update instead."""
        remaining = list(live)
        for ref, cards, digest in existing_markers(route, where):
            covered = [c for c in cards if c in remaining]
            if not covered or set(cards) - set(board.cards):
                continue
            if marker_hash(cards, board) != digest:
                skipped.append("%s: %s carries an older answer; not treated as harvested" % (",".join(covered), ref))
                continue
            _mark(board, covered, ref)
            skipped.append("%s found in existing %s (harvest record repaired)" % (",".join(covered), ref))
            remaining = [c for c in remaining if c not in covered]
        return remaining

    created, skipped, pending_cmds = [], [], []
    for n, d in enumerate(drafts, 1):
        live = [c for c in d["cards"] if board.state(c) != "harvested"]
        for cid in d["cards"]:
            if cid not in live:
                skipped.append("%s already harvested → %s" % (cid, board.harvest["cards"][cid]["target"]))
        if not live:
            continue
        marker = draft_marker(board_id, live, board)
        footer = "\n\n---\n\nHarvested from decision board `%s`%s · cards %s\n\n%s\n" % (
            board_id, " ([record](%s))" % link if link else "", ", ".join(sorted(live)), marker)
        body = d["body"].rstrip("\n") + footer
        body_file = outdir / ("draft-%02d.md" % n)
        body_file.write_text(body, encoding="utf-8")
        if d["route"] == "issue":
            target_desc = "new issue in %s: %s" % (d["repo"], d["title"])
            cmd = ["gh", "issue", "create", "--repo", d["repo"], "--title", d["title"], "--body-file", str(body_file)]
            for label in d.get("labels", []):
                cmd += ["--label", label]
        elif d["route"] == "comment":
            repo, num = ISSUE_REF_RE.match(d["issue"]).groups()
            target_desc = "comment on %s" % d["issue"]
            cmd = ["gh", "issue", "comment", num, "--repo", repo, "--body-file", str(body_file)]
        else:
            target_desc = "vault note %s" % d["path"]
            cmd = None

        print("── draft %d · %s · cards %s" % (n, target_desc, ", ".join(live)))
        if args.dry_run:
            print(body)
            continue

        if d["route"] in ("issue", "comment"):
            # A previous run may have written this already and lost its harvest record: repair, never duplicate.
            remaining = repair(d["route"], d["repo"] if d["route"] == "issue" else d["issue"], live)
            if not remaining:
                continue
            if remaining != live:
                raise BoardError("draft %d is only partly on GitHub already (%s still missing); split the draft "
                                 "so each part can be written once" % (n, ", ".join(remaining)))
        if d["route"] == "vault":
            vault = os.environ.get("MEMORY_VAULT_PATH")
            if not vault:
                raise BoardError("route vault needs MEMORY_VAULT_PATH")
            dest = Path(vault) / d["path"]
            if args.execute:
                if dest.exists() and marker.split(" hash=")[0] not in dest.read_text(encoding="utf-8"):
                    raise BoardError("%s already exists and is not from this board; choose another path" % dest)
                dest.parent.mkdir(parents=True, exist_ok=True)
                atomic_write(dest, body)
                _mark(board, live, "vault:" + d["path"])
                created.append("vault:" + d["path"])
            else:
                pending_cmds.append("cp %s %s" % (shlex.quote(str(body_file)), shlex.quote(str(dest))))
                pending_cmds.append(_mark_cmd(board, live, "vault:" + d["path"]))
            continue
        if args.execute:
            out = gh(*cmd[1:]).strip()
            m = re.search(r"/issues/(\d+)", out)
            if not m:
                raise BoardError("could not read the issue number from gh output: %r" % out)
            ref = ("%s#%s" % (d["repo"], m.group(1))) if d["route"] == "issue" else d["issue"]
            _mark(board, live, ref)
            created.append(ref)
        else:
            pending_cmds.append(" ".join(shlex.quote(c) for c in cmd))
            pending_cmds.append(_mark_cmd(board, live, d["repo"] + "#<N from the line above>" if d["route"] == "issue" else d["issue"]))

    plan = harvest_plan(Board.load(board.path))
    print()
    for line in skipped:
        print("skip: " + line)
    if args.dry_run:
        print("dry run: nothing written, nothing created. Drafts are above.")
    elif args.execute:
        print("created: %s" % (", ".join(created) or "nothing"))
    elif pending_cmds:
        print("run these, in order (each gh command, then the mark-harvested that follows it):")
        for line in pending_cmds:
            print("  " + line)
    else:
        print("nothing to do.")
    left = [c for c in plan["to_harvest"] if c not in set(sum((d["cards"] for d in drafts), []))]
    if left:
        print("decided but in no draft: %s" % ", ".join(left))
    opened = plan["open"]["flagged"] + plan["open"]["stale"] + plan["open"]["untouched"]
    if opened:
        print("still open on the board: %s" % ", ".join(opened))
    print("%d to harvest · %d to update · %d harvested" % (len(plan["to_harvest"]), len(plan["to_update"]), len(plan["harvested"])))
    return 0


def _mark(board, cards, target):
    """Record a harvest in the APP first, then in the frozen export.

    The app first, and the local write only if it succeeded. If the order were
    reversed, or the app write were best-effort, a failed POST would leave a
    board that looks harvested on disk and un-harvested to everyone answering it
    — and the next `freeze`, which re-exports harvest.json FROM the app, would
    quietly delete the local record. Losing the local copy is recoverable (the
    marker on the issue repairs it); losing the app's is not visible at all.
    """
    repo = repo_slug(board.agenda.get("repo") or "")
    api("POST", "/boards/%s/%s/harvest" % (repo, board.agenda["id"]),
        {"cards": list(cards), "target": target})
    records = board.harvest.setdefault("cards", {})
    stamp = now_iso()
    for cid in cards:
        records[cid] = {"target": target, "hash": answer_hash(board.answer(cid)), "at": stamp}
    atomic_write(board.path / HARVEST_FILE, dump_json(board.harvest))
    marked = Board.load(board.path)
    write_generated(marked.path / BOARD_FILE, render_board(marked), check=False)
    if (marked.path.parent / INDEX_FILE).exists():
        write_generated(marked.path.parent / INDEX_FILE, render_index(marked.path.parent), check=False)
    board.harvest = marked.harvest


def _mark_cmd(board, cards, target):
    import shlex
    return "python3 %s mark-harvested %s/%s --cards %s --target %s --into %s" % (
        shlex.quote(str(Path(__file__).resolve())),
        repo_slug(board.agenda.get("repo") or ""), board.agenda["id"],
        ",".join(cards), shlex.quote(target), shlex.quote(str(board.path)))


# --------------------------------------------------------------------------- the app

# A board is HOSTED. `serve` — a 127.0.0.1-bound Python server that owned
# answers.json — was retired with this change (fredabood/.dotfiles#15): it was the
# second writer of a board, and only one of the two renderings you could see was
# writable. The deployed work app is now the only way to answer one.
#
# The split that replaces it:
#
#   OPEN board      -> the app's database is the truth. new / revise / answer /
#                      mark-harvested all go over HTTP.
#   FROZEN board     -> the committed files are the truth. `freeze` writes them.
#   app moved since  -> `drifted`; harvest refuses until you re-freeze.
#
# Everything that reads a DIRECTORY still works unchanged — validate, render,
# index, harvest-plan, harvest-apply — because what they read is a freeze export.
# That is deliberate: it keeps `harvest-plan` usable as a parity oracle against
# the app's own card states, and it is the only fallback for reading a board when
# the mini or the tailnet is down.

# There is NO default host here, and that is not an oversight. This repo is public;
# the address of the estate's own services is private infrastructure and belongs in
# the vault, so the base URL is resolved at runtime from the environment or from
# `$MEMORY_VAULT_PATH/personal/profile.md` — the same pattern the personal-voice
# agent uses for the facts it must not embed.
API_ENV = "DECISION_BOARD_API"
TOKEN_ENV = "JIRA_GRAPH_SERVICE_TOKEN"
PROFILE_KEY = "Decision board API"
BOARD_REF_RE = re.compile(r"^([A-Za-z0-9_.-]+)/(\d{4}-\d{2}-\d{2}-[a-z0-9]+(?:-[a-z0-9]+)*)$")
PROFILE_RE = re.compile(r"^\s*[-*]\s*\*\*%s\*\*\s*:\s*`?(\S+?)`?\s*$" % PROFILE_KEY, re.M)
API_TIMEOUT = 30


def board_snapshot(board):
    """What a page needs besides the agenda: answers, computed states and harvest targets.

    Nothing in this file calls it any more — the page that did lives in the app.
    It stays because it is the SOURCE the app vendors this payload shape from
    (`bin/vendor-boardcore.py`, work#485), pulled out by AST so the two cannot
    drift. Deleting it here would make the app hand-maintain a shape whose whole
    point is agreeing with this file.
    """
    records = board.harvest.get("cards", {})
    return {
        "answers": board.answers,
        "states": dict((cid, board.state(cid)) for cid in board.cards),
        "harvest": dict((cid, rec["target"]) for cid, rec in records.items()),
    }


def profile_api():
    """The API base recorded in the private vault profile, or None.

    Looked up as a `- **Decision board API**: <url>` bullet. Absent vault, absent
    file and absent bullet are all just "not configured" — this is a lookup, not a
    check, and it must not turn a missing vault into a crash.
    """
    root = os.environ.get("MEMORY_VAULT_PATH") or os.path.expanduser("~/Repositories/memory")
    try:
        text = Path(root, "personal", "profile.md").read_text(encoding="utf-8")
    except OSError:
        return None
    m = PROFILE_RE.search(text)
    return m.group(1) if m else None


def api_base():
    base = (os.environ.get(API_ENV) or profile_api() or "").rstrip("/")
    if not base:
        raise BoardError(
            "no boards API configured. Set %s, or add a line to "
            "$MEMORY_VAULT_PATH/personal/profile.md:\n"
            "    - **%s**: https://<host>/api" % (API_ENV, PROFILE_KEY))
    if not (base.startswith("https://")
            or base.startswith("http://127.0.0.1")
            or base.startswith("http://localhost")):
        raise BoardError(
            "%s must be https, or http on loopback for testing; got %r" % (API_ENV, base))
    return base


def api(method, path, body=None):
    """One request to the boards API. Returns the decoded payload.

    The token is read from the environment and never logged — not in an error
    message, not in a URL. Populate it with:

        export JIRA_GRAPH_SERVICE_TOKEN="$(op read 'op://Homelab/Jira Graph Service Token/credential')"
    """
    import urllib.error
    import urllib.request

    url = api_base() + path
    data = None
    headers = {"Accept": "application/json"}
    if body is not None:
        data = dump_json(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
        headers["Content-Length"] = str(len(data))
    token = os.environ.get(TOKEN_ENV, "").strip()
    if token:
        headers["X-Service-Token"] = token
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=API_TIMEOUT) as res:
            return json.loads(res.read().decode("utf-8") or "null")
    except urllib.error.HTTPError as exc:
        detail = ""
        try:
            detail = (json.loads(exc.read().decode("utf-8")) or {}).get("error") or ""
        except (ValueError, OSError):
            pass
        if exc.code in (401, 403):
            detail = detail or ("not authorized — set %s, and reach the app over the tailnet"
                                % TOKEN_ENV)
        raise BoardError("%s %s: %d %s" % (method, path, exc.code, detail or exc.reason))
    except urllib.error.URLError as exc:
        raise BoardError("%s %s: cannot reach %s (%s)" % (method, path, api_base(), exc.reason))


def board_ref(value):
    """Split `<repo>/<board-id>`, the address the app keys a board by.

    `<repo>` is the repo the board DECIDES, which is not always the repo it is
    stored in — a board carrying evidence the decided repo forbids lives with the
    repo that owns the evidence.
    """
    m = BOARD_REF_RE.match(value or "")
    if not m:
        raise BoardError("expected <repo>/<board-id>, e.g. homelab/2026-01-15-team-offsite; got %r"
                         % value)
    return m.group(1), m.group(2)


def cmd_new(args):
    """Publish a new board to the app. Nothing is written to disk.

    Validated locally FIRST so a malformed agenda fails against the file you are
    editing, with line-level messages, rather than as one flattened 400.
    """
    agenda = normalize_agenda(read_json(args.source))
    rep = validate_agenda(agenda)
    if rep.errors:
        raise BoardError("\n".join(["%s: agenda is invalid:" % args.source]
                                   + ["  " + e for e in rep.errors]))
    for cid, card in cards_by_id(agenda).items():
        if card.get("rev", 1) != 1 or card.get("retired"):
            raise BoardError("%s: a new board starts every card at rev 1, not retired" % cid)
    out = api("POST", "/boards", agenda)
    repo = out.get("repo")
    print("created %s/%s (%d cards in %d sections)"
          % (repo, out.get("board_id"), out.get("cards", 0), len(agenda["sections"])))
    print("answer it at %s" % board_url(repo, out.get("board_id")))
    return 0


def board_url(repo, board_id):
    base = api_base()
    return "%s/#/boards/%s/%s" % (base[:-len("/api")] if base.endswith("/api") else base,
                                  repo, board_id)


def cmd_freeze(args):
    """Commit the app's current export into the repo the board decides.

    This is the moment the source of truth moves. Before it, the app is truth and
    the files may not exist; after it, the committed files are the record every
    harvested issue links to, and a later change in the app makes the board
    `drifted` until this is run again.

    The app holds no git credential and does the committing of nothing — it is
    TOLD that a commit happened, and refuses the claim if the board moved between
    the export and the commit.
    """
    import subprocess

    repo, board_id = board_ref(args.board)
    export = api("GET", "/boards/%s/%s/export" % (repo, board_id))
    target = Path(args.into) if args.into else Path("docs/decision-boards") / board_id
    target.mkdir(parents=True, exist_ok=True)
    for name in (AGENDA_FILE, ANSWERS_FILE, HARVEST_FILE, BOARD_FILE):
        atomic_write(target / name, export["files"][name])
    if (target.parent / INDEX_FILE).exists() or any(target.parent.iterdir()):
        write_generated(target.parent / INDEX_FILE, render_index(target.parent), check=False)
    print("exported %s/%s → %s (content %s)" % (repo, board_id, target, export["content_hash"]))

    if args.no_commit:
        print("not committed (--no-commit). Commit these files, then run:")
        print("  board.py freeze %s --into %s --record <sha>" % (args.board, target))
        return 0

    facts = git_facts(target)
    if facts is None:
        raise BoardError("%s is not inside a git repository; a freeze IS a commit" % target)

    sha = args.record
    if not sha:
        paths = [str(target)]
        if (target.parent / INDEX_FILE).exists():
            paths.append(str(target.parent / INDEX_FILE))
        run = subprocess.run(["git", "-C", str(facts["root"]), "add", "--"] + paths,
                             capture_output=True, text=True, timeout=30)
        if run.returncode != 0:
            raise BoardError("git add failed: %s" % (run.stderr or run.stdout).strip())
        staged = subprocess.run(["git", "-C", str(facts["root"]), "diff", "--cached",
                                 "--name-only", "--"] + paths,
                                capture_output=True, text=True, timeout=30)
        if not staged.stdout.strip():
            # Already committed at this content. Re-record rather than refuse: the
            # freeze row, not the working tree, is what harvest reads.
            sha = facts["sha"]
            print("nothing to commit; recording the current HEAD")
        else:
            msg = "decision board: freeze %s at %s" % (board_id, export["content_hash"])
            run = subprocess.run(["git", "-C", str(facts["root"]), "commit", "-m", msg],
                                 capture_output=True, text=True, timeout=60)
            if run.returncode != 0:
                raise BoardError("git commit failed: %s" % (run.stderr or run.stdout).strip())
            head = subprocess.run(["git", "-C", str(facts["root"]), "rev-parse", "HEAD"],
                                  capture_output=True, text=True, timeout=30)
            sha = head.stdout.strip()

    out = api("POST", "/boards/%s/%s/freeze" % (repo, board_id),
              {"sha": sha, "content_hash": export["content_hash"]})
    print("frozen at %s · %s/%s is now git-of-record" % (out["sha"][:12], repo, board_id))
    return 0


def build_parser():
    p = argparse.ArgumentParser(
        prog="board.py",
        description="Decision boards, hosted in the work app and frozen into the repo they decide.")
    sub = p.add_subparsers(dest="command")

    # --- the app owns an OPEN board -----------------------------------------
    s = sub.add_parser("new", help="publish a new board to the app from an agenda")
    s.add_argument("--from", dest="source", required=True)
    s.set_defaults(func=cmd_new)
    s = sub.add_parser("revise", help="replace the agenda in the app, protecting existing answers")
    s.add_argument("board", help="<repo>/<board-id>, e.g. homelab/2026-01-15-team-offsite")
    s.add_argument("--from", dest="source", required=True)
    s.add_argument("--bump", help="comma-separated card ids whose meaning changed")
    s.add_argument("--keep-answer", help="comma-separated card ids that were only reworded")
    s.set_defaults(func=cmd_revise)
    s = sub.add_parser("freeze",
                       help="commit the app's export into the deciding repo; git becomes the record")
    s.add_argument("board", help="<repo>/<board-id>")
    s.add_argument("--into", help="board directory (default: docs/decision-boards/<board-id>)")
    s.add_argument("--no-commit", action="store_true",
                   help="write the files and stop; record the freeze later with --record")
    s.add_argument("--record", help="a commit sha to record, for a freeze you committed yourself")
    s.set_defaults(func=cmd_freeze)
    s = sub.add_parser("mark-harvested", help="record where decided cards landed")
    s.add_argument("board", help="<repo>/<board-id>")
    s.add_argument("--cards", required=True)
    s.add_argument("--target", "--issue", dest="target", required=True)
    s.add_argument("--into", help="also refresh this frozen export's harvest.json and BOARD.md")
    s.set_defaults(func=cmd_mark_harvested)

    # --- these read a DIRECTORY: a freeze export ----------------------------
    # Unchanged on purpose. They keep working with no network, which is the only
    # way to read a board while the app is unreachable, and `harvest-plan` stays
    # usable as a parity oracle against the app's own card states.
    s = sub.add_parser("validate", help="check a frozen export's agenda, answers and harvest records")
    s.add_argument("dir")
    s.set_defaults(func=cmd_validate)
    s = sub.add_parser("render", help="regenerate BOARD.md")
    s.add_argument("dir")
    s.add_argument("--check", action="store_true", help="exit 1 if BOARD.md is out of date; write nothing")
    s.set_defaults(func=cmd_render)
    s = sub.add_parser("index", help="regenerate the README.md index of a boards directory")
    s.add_argument("root")
    s.add_argument("--check", action="store_true", help="exit 1 if README.md is out of date; write nothing")
    s.set_defaults(func=cmd_index)
    s = sub.add_parser("harvest-plan", help="classify every card for harvesting")
    s.add_argument("dir")
    s.add_argument("--format", choices=("json", "text"), default="json")
    s.set_defaults(func=cmd_harvest_plan)
    s = sub.add_parser("harvest-apply", help="turn reviewed drafts into issues, comments or vault notes")
    s.add_argument("dir")
    s.add_argument("--drafts", required=True, help="drafts JSON (schema decision-board-drafts/1)")
    mode = s.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true", help="print the drafts; write and create nothing")
    mode.add_argument("--execute", action="store_true",
                      help="create the issues/comments/notes and record them (refused in repos whose hooks gate issue writes)")
    s.add_argument("--out", help="directory for the prepared body files (default: a new temp dir)")
    s.set_defaults(func=cmd_harvest_apply)
    return p


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    if not getattr(args, "func", None):
        parser.print_help(sys.stderr)
        return 2
    try:
        return args.func(args)
    except BoardError as exc:
        print("error: %s" % exc, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
