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
├── agents/                 # subagents              → ~/.claude/agents/<name>.md
├── commands/               # slash commands         → ~/.claude/commands/<name>.md
├── rules/                  # global rules           → ~/.claude/rules/<name>.md
├── hooks/                  # hook scripts           → ~/.claude/hooks/<name>
├── skills/                 # skills (one dir each)  → ~/.claude/skills/<name>/
├── statusline-command.sh   #                        → ~/.claude/statusline-command.sh
├── settings.base.json      # public half of settings.json (generated, never linked)
├── install.sh              # linker + settings generation
├── scripts/
│   ├── claude-settings     # generate / diff / absorb settings.json
│   ├── merge.jq            # base ⊕ overlay (deep merge, arrays union)
│   ├── subtract.jq         # live ⊖ base (what the overlay must hold)
│   ├── check-public.sh     # gitleaks + private denylist (the repo pre-commit hook)
│   └── omnigent-worktree-patch  # keep Omnigent's worktrees in <repo>/.claude/worktrees
└── tests/
    ├── install.test.sh               # fake-HOME tests for install + settings
    └── memory-access-tracker.test.sh # the hook finds Claude Code's real project dir
```

## How it installs

`~/.claude` is Claude Code's live runtime directory — transcripts, prompt history, jobs, backups
of `~/.claude.json` with OAuth data. It is **never linked as a whole**. Each item is linked on its
own, so `~/.claude/{agents,commands,rules,hooks,skills}` stay real directories: anything Claude or
a third-party installer writes there stays out of this repo, and only what is committed here is
managed.

```bash
~/.dotfiles/claude/install.sh             # link everything, prune dangling links, sync settings
~/.dotfiles/claude/install.sh --status    # health check; exit 1 if anything is off
~/.dotfiles/claude/install.sh --dry-run   # show what would change
```

Anything it replaces is moved to `~/.claude-migration-backup/<timestamp>/` — never inside
`~/.claude`, where a backed-up skill directory would load as a duplicate skill.

**After adding or removing an item, re-run `install.sh`.** Edits to an existing item need nothing:
the link already points here.

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

```bash
claude/scripts/claude-settings status    # clean | drift | apply pending | CONFLICT
claude/scripts/claude-settings diff      # live vs base + overlay
claude/scripts/claude-settings sync      # absorb drift, regenerate (what install.sh runs)
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

- **A skill**: `claude/skills/<name>/SKILL.md`, then `install.sh`.
- **An agent / command / rule**: `claude/<kind>/<name>.md`, then `install.sh`.
- **A hook**: script in `claude/hooks/` (executable), then register it in `settings.base.json` with
  `$HOME/.claude/hooks/<name>` and run `install.sh`.
- **Anything needing a personal fact**: add the fact to the vault's `personal/profile.md` and have the
  prompt read it there.

The pre-commit hook (`.githooks/pre-commit` → `scripts/check-public.sh --staged`) runs gitleaks and
the vault's private denylist over every staged change. `install.sh` at the repo root enables it
with `git config core.hooksPath .githooks`.

## Tests

```bash
bash claude/tests/install.test.sh
bash claude/tests/memory-access-tracker.test.sh
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

- **A Claude Code update stops loading linked items**: `install.sh --materialize` replaces every
  managed link with a real copy; re-run plain `install.sh` to relink once fixed.
- **Settings look wrong**: `claude-settings diff`, then `apply --force` (live is backed up), or
  restore a `settings.json` from `~/.claude-migration-backup/`.
- **Undo the links entirely**:
  `find ~/.claude/{agents,commands,rules,hooks,skills} -maxdepth 1 -type l -lname "$HOME/.dotfiles/claude/*" -delete`

## History

Until 2026-09-10 this config was the separate public repo `fredabood/.claude`, checked out directly
at `~/.claude`. It moved here without its history (1,300+ commits of an unrelated predecessor
framework and old infrastructure notes); a full mirror is kept privately.
