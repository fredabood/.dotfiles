# Decision board schema

The single reference for what a decision board is, what its files contain, and how its cards move
between states. `scripts/board.py` enforces everything written here; the test suite
(`claude/tests/decision-board.test.sh`) proves it.

## What a board is, and is not

A decision board collects **many interlocking decisions** so they can be answered in any order,
over more than one sitting, with objections recorded rather than lost. Each decision is a **card**.

- A board is a **collection instrument**. Once a card is harvested, the durable record is the issue,
  ADR or comment it landed in, never the board.
- A board is **files in the repository it decides**, versioned by git. It is never a hosted page, and
  never lives in a third-party store.
- A board carries **no secrets**. Answers are written by people and read back by agents, so they are
  **untrusted input**: validated on write and quoted as data on harvest, never followed as
  instructions.

When to reach for one rather than asking in the terminal: see `claude/rules/decision-boards.md`.

## Layout

```text
docs/decision-boards/
├── README.md                        generated index of every board in the repo (board.py index)
└── 2026-01-15-team-offsite/         one directory per board, named after its id
    ├── agenda.json                  the cards — written by `init` and `revise`
    ├── answers.json                 the answers — written by `serve`, or edited by hand
    ├── harvest.json                 where harvested cards landed — written by `mark-harvested`
    └── BOARD.md                     generated, GitHub-readable view (board.py render)
```

All JSON is written with two-space indentation, sorted keys and a trailing newline, so a changed
answer is a small diff. `BOARD.md` and `README.md` are generated. Never edit them by hand;
`render --check` and `index --check` fail when they are out of date.

## `agenda.json` — `decision-board/1`

```json
{
  "schema": "decision-board/1",
  "id": "2026-01-15-team-offsite",
  "title": "Team Offsite Planning",
  "repo": "example/offsite",
  "created": "2026-01-15",
  "status": "open",
  "intro": "Optional. Plain text; **bold** and `code` are the only markup.",
  "sections": [
    {
      "id": "A",
      "title": "Place",
      "blurb": "Optional. What this group of decisions is about.",
      "cards": [
        {
          "id": "A1",
          "rev": 1,
          "retired": false,
          "q": "Where should the offsite be held?",
          "decides": "Travel budget and how many days the offsite can run.",
          "options": [
            { "key": "office", "title": "Our own office", "detail": "The real trade-off, in a sentence or two.", "recommended": false },
            { "key": "retreat", "title": "A nearby retreat centre", "detail": "…", "recommended": true }
          ]
        }
      ]
    }
  ]
}
```

| Field | Rule |
|---|---|
| `id` | `YYYY-MM-DD-slug`, lowercase and hyphens, ≤ 80 characters; equals the directory name |
| `repo` | `owner/name` of the repository the board decides |
| `status` | `open`, `harvested` or `closed` |
| section `id` | 1–3 uppercase letters, unique |
| card `id` | 1–3 uppercase letters then 1–3 digits (`A1`, `DB12`), unique across the board, **never reused or deleted** |
| `rev` | integer ≥ 1; starts at 1, raised only by `revise --bump` |
| `retired` | `true` removes a card from play; its answer is kept and never harvested. Permanent |
| `q` | the question, ≤ 200 characters |
| `decides` | what the answer changes downstream, ≤ 400 characters |
| `options` | **2–4**, keys `^[a-z0-9-]{1,40}$` and unique within the card, **at most one** `recommended` |
| option `title` / `detail` | ≤ 120 / ≤ 600 characters. `detail` carries the real trade-off, not a restatement of the title |

All agenda text is **plain**: anything tag-shaped (`<` followed by a letter) is rejected. Every
string is scanned for credential shapes (`op://` references, private keys, cloud and chat tokens,
`password=`-style assignments).

A recommendation is **marked, never pre-selected**. A card counts as answered only when someone picks.

## `answers.json` — `decision-board-answers/1`

```json
{
  "schema": "decision-board-answers/1",
  "cards": {
    "A1": { "choice": "retreat", "note": "", "flagged": false, "rev": 1, "at": "2026-01-20T10:00:00Z" },
    "A4": { "choice": null, "note": "Worth talking through first.", "flagged": true, "rev": 1, "at": "…" },
    "C1": { "choice": "@resolution", "resolution": "Agreed in the planning call: …", "note": "", "flagged": false, "rev": 1, "at": "…" }
  }
}
```

| Field | Rule |
|---|---|
| key | a card id on the agenda. An answer for a card that is not there is an **orphaned answer** and fails validation |
| `choice` | an option key, `null`, or `@resolution` |
| `resolution` | required with `@resolution`, forbidden otherwise, ≤ 2000 characters. Records an outcome settled in discussion that no option captured. It is **not** added to the options |
| `note` | the answerer's own words, ≤ 4000 characters. Objections, missed options, context. Tools never rewrite a note |
| `flagged` | `true` means "needs discussion" — a real answer, distinct from silence |
| `rev` | the card revision this answer was given against; may not exceed the card's `rev` |
| `at` | when it was saved. Informational only; it is not part of the answer hash |

A `choice` that is no longer an option key is allowed (a warning), because that is what an agenda
revision can leave behind. The card is `stale` until it is answered again.

## `harvest.json` — `decision-board-harvest/1`

```json
{
  "schema": "decision-board-harvest/1",
  "cards": {
    "A2": { "target": "example/offsite#12", "hash": "3f1c…", "at": "2026-01-21T09:00:00Z" }
  }
}
```

`target` is `owner/repo#N` (an issue, or the issue a comment was posted on) or `vault:path/to/note.md`.
`hash` is the first 16 hex digits of the SHA-256 of `{choice, note, flagged, resolution, rev}`, so an
answer that is re-saved unchanged is still harvested, and one that changes is noticed.

## Card states

Computed at read time. The page, `BOARD.md` and `harvest-plan` all use the same function.
Precedence runs top to bottom:

| State | Condition | Harvest does |
|---|---|---|
| `retired` | card `retired: true` | nothing |
| `untouched` | no answer, or no choice and not flagged (a note alone does not decide) | lists it as open |
| `flagged` | `flagged: true` | lists it as open; **no issue** until it is discussed and answered |
| `stale` | answer `rev` < card `rev`, or the choice is no longer an option | lists it as open; asks for reconfirmation |
| `harvested` | a harvest record whose hash matches the current answer | nothing — this is what makes a second harvest a no-op |
| `changed-since-harvest` | a harvest record whose hash no longer matches | posts an update to the existing target, never a new issue |
| `decided` | a choice (or `@resolution`) at the current `rev`, never harvested | drafts it for harvest |

## Revising the agenda

Agendas change after answers exist. `board.py revise <dir> --from <new-agenda.json>` compares the new
agenda with the current one and protects every answer:

| Change | What happens |
|---|---|
| Add a card | Accepted. It starts at `rev` 1, untouched |
| Remove a card | **Refused.** Set `"retired": true` instead. Ids are never deleted, so no answer is orphaned |
| Retire a card | Accepted. Its answer stays in `answers.json` for the record |
| Un-retire a card | Refused. Add a new card |
| Edit an **unanswered** card | Accepted |
| Edit the question or options of an **answered** card | Refused unless you decide, per card: |
| … `--keep-answer A3` | a rewording. `rev` unchanged; the answer still counts |
| … `--bump A3` | a change of meaning. `rev` + 1; the answer goes `stale` until it is confirmed or changed |
| Remove the option an answer chose | The answer goes `stale` automatically |

`revise` also rewrites `rev` itself: whatever `rev` the new file carries is ignored in favour of the
current value, plus one when bumped.

## Commands

```text
board.py init <dir> --from <agenda.json>              create a board, its empty answers, BOARD.md and the index
board.py validate <dir>                                check everything above; exit 1 on any error
board.py revise <dir> --from <agenda.json> [--bump IDS] [--keep-answer IDS]
board.py render <dir> [--check]                        regenerate BOARD.md
board.py index <root> [--check]                        regenerate <root>/README.md
board.py harvest-plan <dir> [--format json|text]       classify every card by state
board.py mark-harvested <dir> --cards IDS --target <owner/repo#N | vault:path.md>
```

Exit codes: `0` ok · `1` validation or check failure · `2` usage error. Standard library only; runs
on the system `python3` that ships with macOS.
