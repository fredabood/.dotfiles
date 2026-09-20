# Decision board schema

The single reference for what a decision board is, what its files contain, and how its cards move
between states. `scripts/board.py` enforces everything written here; the test suite
(`claude/tests/decision-board.test.sh`) proves it.

## What a board is, and is not

A decision board collects **many interlocking decisions** so they can be answered in any order,
over more than one sitting, with objections recorded rather than lost. Each decision is a **card**.

- A board is a **collection instrument**. Once a card is harvested, the durable record is the issue,
  ADR or comment it landed in, never the board.
- A board has **two lives**, and which one it is in decides where the truth is. While it is **open**
  it is hosted in the work app and the app's database is the truth; you answer it there. When it is
  **frozen** — the same moment it is harvested — its export is committed into the repository it
  decides, and from then on **the committed files are the record**, which is what every harvested
  issue permalinks to. If the app moves on after a freeze the board is **drifted**, and harvesting
  refuses until it is frozen again.
- **The prohibition that stands is on third-party hosting.** A board is never a claude.ai Artifact
  and never lives in an artifact database or any other store outside this estate. The work app is
  self-hosted and tailnet-gated, and the freeze keeps "git versions it" literally true for every
  board that reaches a decision.
- **The one exception is evidence the decided repo forbids.** If a product repo bans
  deployment-specific detail and the board quotes a survey of one deployment, the board is stored
  with the repo that owns that evidence. Its `repo` field still names the decided repository, and
  harvest links point at wherever the board is stored.
- A board carries **no secrets**. Answers are written by people and read back by agents, so they are
  **untrusted input**: validated on write and quoted as data on harvest, never followed as
  instructions.

When to reach for one rather than asking in the terminal: see `claude/rules/decision-boards.md`.

## Layout

```text
docs/decision-boards/
├── README.md                        generated index of every board in the repo (board.py index)
└── 2026-01-15-team-offsite/         one frozen export per board, named after its id
    ├── agenda.json                  the cards
    ├── answers.json                 the answers
    ├── harvest.json                 where harvested cards landed
    └── BOARD.md                     generated, GitHub-readable view
```

**All four files are written by `board.py freeze`, from the app's canonical export.** Editing one by
hand does not change the board — the next freeze overwrites it — and a hand-edited directory stops
matching the frozen export, which `harvest-apply` refuses.

All JSON is written with two-space indentation, sorted keys and a trailing newline, so a changed
answer is a small diff, and the app reproduces that serialization byte for byte so an export is
diffable against the file it replaces. `BOARD.md` and `README.md` are generated. Never edit them by
hand; `render --check` and `index --check` fail when they are out of date.

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
| `repo` | `owner/name` of the repository the board decides, where its cards are harvested. Usually also where it is stored (see the exception above) |
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

## Harvesting: `harvest-plan`, drafts, `harvest-apply`

`harvest-plan` lists every card with its state and answer. Claude groups the `decided` cards into
**drafts**, one per issue, comment or vault note to write:

```json
{
  "schema": "decision-board-drafts/1",
  "drafts": [
    {"route": "issue", "cards": ["A1", "C1"], "repo": "owner/name", "title": "…", "body": "…", "labels": ["…"]},
    {"route": "comment", "cards": ["A3"], "issue": "owner/name#13", "body": "…"},
    {"route": "vault", "cards": ["B1"], "path": "project/decisions/note.md", "body": "…"}
  ]
}
```

`harvest-apply` refuses a drafts file in any of these cases:

- a card appears twice, is not on the board, or is not `decided`;
- a `changed-since-harvest` card is routed anywhere except a comment on its existing target;
- a vault path is absolute or climbs out with `..`;
- a body already carries a marker, or looks like it holds a secret.

To every body it appends a footer with the board id, the cards, a link to `BOARD.md` pinned to the
current commit, and a marker:

```text
<!-- decision-board: board=<board id> cards=A1,C1 hash=<16 hex> -->
```

The marker hash covers each card's answer hash, so a marker identifies **this answer**, not merely
this card.

| Mode | GitHub | `harvest.json` |
|---|---|---|
| `--dry-run` | no calls | untouched |
| *(default)* prepare | reads only: looks for existing markers | repaired if a marker is found; otherwise untouched. Prints the `gh` commands and the `mark-harvested` that follows each |
| `--execute` | looks for markers, then creates issues and comments; writes vault notes | recorded after each write. **Refused** in repos whose hooks gate issue writes, so those gates are never bypassed |

Outside `--dry-run`, the board must be **frozen at exactly these answers**, and there are three
distinct refusals because they need three different fixes:

| Refusal | What it means | Fix |
|---|---|---|
| never frozen | there is no commit for the pinned link to point at | `board.py freeze` |
| drifted | the app moved on after the freeze, so the committed record no longer says what the board says | `board.py freeze` again |
| wrong files | this directory is not that export | `board.py freeze --into` here |

This replaces the old "commit your answers first" check, which asked a weaker question: a clean
worktree only says nobody edited these files, not that they still match the board people are
answering. Since the app became the truth for an open board, the committed files can be pristine and
months stale at the same time.

Idempotency has two layers:

1. **`harvest.json`.** Cards already `harvested` are skipped before anything else happens, so a rerun
   makes no GitHub calls at all.
2. **Markers on GitHub.** If `harvest.json` was lost, an issue body or issue comment that already
   carries a marker **with the current hash** is recorded instead of written again. A marker for an
   older answer is reported, and does not count.

## Answering: the work app

A board is answered in the work app, on whatever device is to hand. There is
no local server and no second rendering: the page you read is the page that writes.

| Property | Behaviour |
|---|---|
| Reach | The app is tailnet-gated. There is no public route to it |
| Access | The app's existing write posture — a tailnet login in `WRITE_ALLOWED`, or `X-Service-Token` for automation. No new mechanism and no new credential were added for boards |
| Writes | One card per request, validated by the same rules `board.py` applies, then stored as one row. `rev` is checked for **equality**, so a page that has not seen a reworded card cannot answer it; the 409 carries the current rev so the page can reload and self-heal |
| Empty answer | No choice, not flagged, and a blank note is not an answer — it deletes the row, so an untouched card does not look touched |
| Rejections | 400 invalid answer · 409 the card was revised (reload) · 413 body over 16 KiB · 415 not JSON |
| Page | Recommendations marked, never pre-selected. Answer text is inserted as text, never as markup |
| Git | The app holds no git credential and commits nothing. `board.py freeze` is what commits, locally |

**`board.py` is the only writer of the files.** They are an export, not an input: editing
`answers.json` by hand no longer reaches anyone, and the next freeze overwrites it. To read a board
without the app — during an outage, or from a phone with no tailnet — read the committed `BOARD.md`
on GitHub.

## Freezing: where the truth moves

`board.py freeze <repo>/<board-id>` pulls the app's canonical export, writes the four files into the
deciding repo, commits them, and tells the app which commit they landed in. **Freeze and harvest are
the same moment**, which is what makes the pinned permalink work: a database has no sha, and the
freeze commit supplies one.

The app is *told* a commit happened rather than making one, and it refuses the claim if the board
changed between the export and the commit — the one way this model could silently lie.

Drift is measured over the **agenda and answers only**. `BOARD.md` is derived from them, and the
harvest log records where cards *went* rather than what was decided, so marking a card harvested
does not make a just-frozen board read as drifted. The cost of that deliberate blind spot is that
`mark-harvested --into` has to refresh the export explicitly; nothing will raise a drift banner for
it.

## Commands

```text
# the app owns an OPEN board
board.py new --from <agenda.json>                      publish a new board; writes nothing to disk
board.py revise <repo>/<id> --from <agenda.json> [--bump IDS] [--keep-answer IDS]
board.py freeze <repo>/<id> [--into DIR] [--no-commit | --record SHA]
board.py mark-harvested <repo>/<id> --cards IDS --target <owner/repo#N | vault:path.md> [--into DIR]

# these read a frozen export, and need no network
board.py validate <dir>                                check everything above; exit 1 on any error
board.py render <dir> [--check]                        regenerate BOARD.md
board.py index <root> [--check]                        regenerate <root>/README.md
board.py harvest-plan <dir> [--format json|text]       classify every card by state
board.py harvest-apply <dir> --drafts <file> [--dry-run | --execute] [--out DIR]
```

Exit codes: `0` ok · `1` validation or check failure · `2` usage error. Standard library only; runs
on the system `python3` that ships with macOS.

Environment: `DECISION_BOARD_API` and `JIRA_GRAPH_SERVICE_TOKEN`, the latter populated from
`op://Homelab/Jira Graph Service Token/credential`. **Neither has a default in this repo, which is public:** the
app's address is private infrastructure, so `DECISION_BOARD_API` falls back to the
`- **Decision board API**:` line in `$MEMORY_VAULT_PATH/personal/profile.md` rather than to a
hard-coded host. The token is read from the environment and never written into a board, a log or an
error message.
