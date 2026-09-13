# claude/ — Claude Code configuration

Shared, portable Claude Code config: agents, slash commands, rules, hooks, skills, the status line
and the public half of `settings.json`. `install.sh` links it into `~/.claude`.

**This repo is public. Nothing personal lives here.** Affiliations, email domains, voice profiles,
vault names and the private half of `settings.json` live in the private memory vault
(`$MEMORY_VAULT_PATH`, default `~/Repositories/memory`) under `personal/`, and the prompts that need
them read `$MEMORY_VAULT_PATH/personal/profile.md` at runtime.

## Layout

```
claude/
├── agents/                 # subagents              ← ~/.claude/agents   (folder link)
├── commands/               # slash commands         ← ~/.claude/commands (folder link)
├── rules/                  # global rules           ← ~/.claude/rules    (folder link)
├── hooks/                  # hook scripts           ← ~/.claude/hooks    (folder link)
├── skills/                 # skills (one dir each)  ← ~/.claude/skills   (folder link)
├── statusline-command.sh   #                        → ~/.claude/statusline-command.sh
├── settings.base.json      # public half of settings.json (generated, never linked)
├── install.sh              # linker + settings generation
├── scripts/
│   ├── claude-settings     # generate / diff / absorb settings.json
│   ├── merge.jq            # base ⊕ overlay (deep merge, arrays union)
│   ├── subtract.jq         # live ⊖ base (what the overlay must hold)
│   ├── check-public.sh     # gitleaks + private denylist (the repo pre-commit hook)
│   ├── memory-cleanup.py   # auto-memory staleness report (reads memory-access-tracker frontmatter)
│   └── omnigent-worktree-patch  # keep Omnigent's worktrees in <repo>/.claude/worktrees
└── tests/
    ├── decision-board.test.sh        # board.py: schema, states, revision, serve, harvest
    ├── install.test.sh               # fake-HOME tests for install + settings
    ├── memory-access-tracker.test.sh # the hook finds Claude Code's real project dir
    └── memory-cleanup.test.sh        # the staleness report scans every project memory dir
```

## How it installs

The five content folders — `agents`, `commands`, `rules`, `hooks`, `skills` — are each linked
whole: `~/.claude/skills → ~/Repositories/dotfiles/claude/skills`, and so on. **Anything added, edited or
removed here takes effect in `~/.claude` immediately; nothing needs re-running.** Run `install.sh`
once per machine.

`~/.claude` **itself is never linked.** It is Claude Code's live runtime directory — transcripts,
prompt history, jobs, backups of `~/.claude.json` with OAuth data, `settings.local.json` — and it
stays out of this public repo.

The trade-off of linking the folders: anything written *into* them lands in this working tree — a
skill installed by a third-party tool, an agent created with `/agents`. That is what makes new items
sync, and it also means a stray install is one `git add -A` from being published. `install.sh
--status` lists every uncommitted item in the five folders; commit what you mean to share, delete
the rest.

```bash
~/Repositories/dotfiles/claude/install.sh             # link the folders + statusline, sync settings
~/Repositories/dotfiles/claude/install.sh --status    # health check + uncommitted items; exit 1 if unhealthy
~/Repositories/dotfiles/claude/install.sh --dry-run   # show what would change
```

If a folder in `~/.claude` is a real directory (a fresh machine where Claude ran first, or the
earlier per-item layout), `install.sh` checks what is inside before replacing it. Links into this
package and identical copies are safe; a copy that differs is kept in the backup with a warning;
**anything it does not manage blocks that folder**, which is left untouched and listed — move those
items into the repo (to share them) or out of `~/.claude`, then re-run.

Replaced folders go to `~/.claude-migration-backup/<timestamp>/` — never inside `~/.claude`, where a
backed-up skill directory would load as a duplicate skill.

## settings.json

```
~/.claude/settings.json = merge(claude/settings.base.json,
                                $MEMORY_VAULT_PATH/personal/claude/settings.overlay.json)
```

Generated, not linked: Claude Code writes user settings *through* a symlink, so a linked file would
put every `/model`, `/config` and "always allow" change into this public working tree. Objects merge
recursively and arrays union, so the overlay can add permissions without replacing the base's.

When Claude changes the file, that is drift against the last generation
(`~/.local/state/dotfiles/claude-settings.lastgen.json`). `sync` absorbs it into the private overlay
— only when `merge(base, live − base) == live`, i.e. nothing would be lost — then regenerates.

**You never run `sync` by hand.** `hooks/claude-settings-sync.sh` is registered as a `SessionStart`
hook in `settings.base.json`, so every new session:

1. exits immediately if live, base and overlay are unchanged since the last sync (a few `cksum`s);
2. otherwise runs `sync` — absorbing what `/config`, `/model` or "always allow" changed last
   session, and applying base/overlay changes you pulled;
3. commits just the overlay in the vault when it absorbed something, and pushes it in the
   background if the vault branch has an upstream;
4. if `sync` refuses, leaves everything as-is and shows one warning ("Claude settings sync needs
   attention…") in the session — every session, until it is resolved.

It never blocks a session. Log: `~/.local/state/dotfiles/claude-settings-sync.log`. Opt out with
`CLAUDE_SETTINGS_SYNC=0` (no sync) or `CLAUDE_SETTINGS_AUTOCOMMIT=0` (sync, but leave committing to you).

For inspection or manual resolution:

```bash
claude/scripts/claude-settings status    # clean | drift | apply pending | CONFLICT
claude/scripts/claude-settings diff      # live vs base + overlay
claude/scripts/claude-settings sync      # absorb drift, regenerate (what the hook and install.sh run)
claude/scripts/claude-settings apply --force   # generated wins; live is backed up first
```

It refuses, and changes nothing, when:

- live removed or rewrote something the base defines — an overlay cannot express that; edit
  `settings.base.json` here instead (or `absorb --force` to accept the base re-adding it);
- live drifted **and** the base or overlay also changed since the last generation (a conflict);
- there is no generation record and live differs (a machine where Claude ran first).

Put public, portable preferences in `settings.base.json`. Hostnames, internal domains, machine
paths and anything else private go in the overlay.

## Adding things

Create it here and commit it; it is live in `~/.claude` as soon as the file exists.

- **A skill**: `claude/skills/<name>/SKILL.md`.
- **An agent / command / rule**: `claude/<kind>/<name>.md`.
- **A hook**: script in `claude/hooks/` (executable), then register it in `settings.base.json` with
  `$HOME/.claude/hooks/<name>` — the SessionStart sync picks the registration up next session.
- **Anything needing a personal fact**: add the fact to the vault's `personal/profile.md` and have the
  prompt read it there.

The pre-commit hook (`.githooks/pre-commit` → `scripts/check-public.sh --staged`) runs gitleaks and
the vault's private denylist over every staged change. `install.sh` at the repo root enables it
with `git config core.hooksPath .githooks`.

## Tests

```bash
bash claude/tests/install.test.sh
bash claude/tests/memory-access-tracker.test.sh
bash claude/tests/decision-board.test.sh   # starts local servers on 127.0.0.1; uses docker for markdownlint if present
```

Runs against a throwaway `HOME`; never touches the real `~/.claude`, vault or state. Keep the
scripts compatible with macOS `/bin/bash` 3.2.

## Worktrees and Omnigent

`rules/worktrees.md` keeps every repo's worktrees at `<repo>/.claude/worktrees/<name>`. Omnigent
hardcodes a sibling `<repo>-worktrees/` directory instead, with no setting for it, so its installed
copy is patched:

```bash
claude/scripts/omnigent-worktree-patch           # after every `uv tool upgrade omnigent`
claude/scripts/omnigent-worktree-patch --check   # exit 1 if an upgrade reverted it
```

Restart the Omnigent host afterwards. Exit 2 means the patched line no longer exists upstream —
read `omnigent/host/git_worktree.py` before changing the script.

## Recovery

- **A Claude Code update stops loading linked folders**: `install.sh --materialize` replaces the
  agents/commands/rules/skills links with real copies (hooks stays linked); re-run plain
  `install.sh` to relink once fixed — identical copies are replaced without complaint.
- **Settings look wrong**: `claude-settings diff`, then `apply --force` (live is backed up), or
  restore a `settings.json` from `~/.claude-migration-backup/`.
- **Undo the links entirely**: `for f in agents commands rules hooks skills; do rm ~/.claude/$f && cp -R ~/Repositories/dotfiles/claude/$f ~/.claude/$f; done`
  (no trailing slash on `rm`, so only the links go).

## History

Until 2026-09-10 this config was the separate public repo `fredabood/.claude`, checked out directly
at `~/.claude`. It moved here without its history (1,300+ commits of an unrelated predecessor
framework and old infrastructure notes); a full mirror is kept privately.
