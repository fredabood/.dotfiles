---
description: Knowledge persistence — where decisions, docs, memories and vault notes go, when to write them, and the vault's structural conventions
---

# Knowledge Persistence — Memory, Docs and Vault

The single home for **where knowledge goes, and when**. It merges the former `memory-management.md`
and `documentation.md` (LAB-2796). When `/workflow` is active, persistence is its Phase 8 gate.
A repo's own `CLAUDE.md` wins where it says more.

## Two systems: don't cross the boundary

- **Auto-memory** (`~/.claude/projects/.../memory/`) answers *"how should Claude behave?"* Types:
  `user` (role, preferences), `feedback` (corrections, plus confirmed approaches), `reference`
  (external resources), `project` (lightweight ongoing-work context).
- **Vault** (`$MEMORY_VAULT_PATH`) answers *"what does the project know?"* It is exported from
  `~/Repositories/dotfiles/zsh/.zshenv` and resolves to `~/Repositories/memory`, the standalone
  `fredabood/memory.md` repo. It is **one central repo** for every project, kept that way for
  cross-project links and a single embedding index.
- **Personal information goes only in vault `personal/`**: identity, employers and clients, email
  domains, addresses, label taxonomies, vault names, private infra, private settings overlays. It
  never goes in this config, which is published from a public repo. A shared prompt or skill that
  needs a personal fact reads `$MEMORY_VAULT_PATH/personal/profile.md` at runtime.

## Routing — where each kind of knowledge goes

| Knowledge | Destination |
|---|---|
| Ticket-specific approach or trade-off; plans, milestones, post-mortems, verification | Issue comment |
| Claude behaviour: user preferences, feedback, corrections | Auto-memory |
| Architectural decision ("chose X over Y because Z") | Vault `homelab/decisions/` |
| Operational knowledge (how to run, deploy, configure) | Vault `homelab/knowledge/<category>/`, or the repo's `docs/` |
| Research (evaluation, comparison, analysis) | Vault `homelab/research/` |
| Session continuity | Vault `homelab/sessions/` (via `/handoff`) |
| Sprint plans and roadmaps / milestones / project context and specs | Vault `homelab/planning/` / `milestones/` / `context/` |
| Personal information | Vault `personal/` |
| Workflow conventions | `CLAUDE.md` (rarely) |

## When to persist

**Immediately**, not deferred to the end of the session:

- the user corrects your approach → `feedback`
- the user shares a role, preference or context → `user`
- a new external resource → `reference`
- an architectural decision → `decisions/`
- new operational knowledge → `knowledge/`
- significant research → `research/`
- a parent issue completed → `milestones/`

**If it is substantial:** a session handoff (`sessions/`); a change to an operational doc (update
the existing note); a sprint plan not already in the tracker (`planning/`).

**On any code change:** if it affects behaviour described in `docs/`, update those docs **in the same
commit**. Never leave docs out of sync with code.

**At session end or handoff:** decisions and learnings are persisted, not just stated in the
conversation (`/handoff`).

## What not to save

- Code patterns, architecture, or anything else derivable from the code or git history
- Transient debugging state, test or CI output
- Anything already in the tracker. Don't duplicate it.
- Ephemeral details that only matter to the current conversation
- Comments on self-explanatory code, or docs for one-off scripts

## Quality bar and hygiene

- **Durability:** will it matter in 30 days? If not, a ticket comment at most.
- **Uniqueness:** search first. For the vault, use the obsidian MCP by title and aliases. For memory,
  check `MEMORY.md`.
- **Actionability:** can a future session act on it?
- **Update rather than create** when it is the same decision, technology or entity, or when it
  corrects or supersedes earlier content. Create when it is a distinct decision (a different
  trade-off or date), an independent finding, or a new handoff. When in doubt, update:
  fragmentation hurts retrieval.
- When observation proves a memory wrong, update or delete it.
- Keep `MEMORY.md` under 200 lines, and consolidate as it approaches that.
- At session start, scan `MEMORY.md` for relevant entries. When resuming a topic, read its
  `sessions/` handoff.

## Vault structural conventions

**Frontmatter is required on every vault `.md`:**

```yaml
---
title: <Note title>
tags:
  - <tag-in-kebab-case>
created: YYYY-MM-DD
---
```

Optional fields: `type`, `aliases`, `entities`, `importance`, `source`, `_migrated`,
`last_accessed`, `access_count`.

- **Filenames:** kebab-case in technical and operational directories. Title Case is acceptable in
  `reference/` and at the vault root.
- **Links:** `[[note-name]]` wikilinks, not markdown links. Link related notes.
- **Staleness (auto-memory):** `memory-access-tracker.sh` maintains `last_accessed` and
  `access_count`. Files unused for 90+ days are candidates for archiving. Report with
  `python3 ~/Repositories/dotfiles/claude/scripts/memory-cleanup.py` (`--dir` for one directory,
  `--archive` to move stale files to `stale/`).
- **Pre-commit:** `memory-frontmatter-check.sh` blocks a vault commit (in the primary checkout or any
  worktree) whose `.md` files are missing `title`, `tags` or `created`.
  - It resolves the repo from `git -C`, a leading `cd … &&`, or the session cwd.
  - It reads the file set from the index, an earlier `git add` in the same command, `commit -a` or
    `commit <paths>`.
  - When it cannot tell, for example with `git add -p` or `git add $(…)`, it prints a `skipped`
    notice and a `0 .md file(s) examined` line; with `--no-verify` the skip blocks.
  - Otherwise it prints `<n> .md file(s) examined`, or a `ZERO-INPUT-OK` reason when the commit has no
    `.md` content.
  - When the file list itself cannot be computed (the resolver failed, or a git call listing the
    commit failed, e.g. on a corrupt index), it blocks rather than passing unchecked; so does the
    secret scan below (LAB-2858). So does an abort once the commit is known to be a vault commit
    (LAB-2948).
  - It validates renamed-and-edited and typechanged notes as additions, so a pure `git mv` of a note
    without frontmatter is blocked until the note gets frontmatter.
  - It validates the staged blob as well as the working-tree file, so a staged-then-deleted note is
    caught.
  - **Both gates block** (LAB-2948): a commit with `-n`, `--no-verify` or `-c core.hooksPath=…` whose
    file list has a skipped part; `update-index`, `read-tree` or `apply --cached`/`--index` before a
    commit in the same repo, and `commit-tree`; and a vault git alias whose expansion commits. Every
    Bash call mentioning `git` is parsed, which adds latency to each. Both run with PATH pinned to
    the system tool dirs first, launched by `/bin/bash`.
  - **Not covered:** a commit or alias whose directory cannot be resolved, or one run with an explicit
    `--git-dir`/`--work-tree`/`GIT_DIR`, and a `gitleaks` planted earlier on PATH.
  - `/obsidian-lint --fix` repairs findings.
- **Pre-commit secret scan:** `memory-gitleaks-check.sh` runs gitleaks with the vault's
  `.gitleaks.toml` (HEAD's committed copy, so a commit cannot allowlist itself) over the files the
  commit will contain, and blocks a finding. It is a keyword-and-entropy check, not a proof: gitleaks'
  default stopwords can suppress a real credential. A missing gitleaks or config blocks too. Human
  kill switch: `MEMORY_GITLEAKS_CHECK=off`. No environment variable can swap its scanner (LAB-2948).
- **Secret scan outside Claude Code (LAB-2857):** the vault's own git hooks, installed into its
  common `.git/hooks` by `claude/install.sh` (`claude/scripts/install-vault-hooks.sh`), run the same
  scan through `claude/scripts/memory-gitleaks-commit-check.sh`.
  - **Covered:**
    - `pre-commit`: terminal, Obsidian desktop, `claude-settings-sync.sh` and every worktree.
    - `pre-push`: every object the push sends that the remote lacks, which means each new file
      version, commit message and tag message. That covers `commit --no-verify`, rebase, cherry-pick,
      am, revert, merges, binary-looking files and tags.
  - **Not covered:**
    - `git push --no-verify`
    - a machine where the hooks were never installed (SessionStart warns)
    - GitHub web edits and Obsidian mobile

    fredabood/homelab#2889 is the backstop for all three.
  - **Not covered: text that is never committed.** vault-sync embeds the working tree
    (fredabood/homelab#2888).
  - **Not covered yet: vault-sync's planned auto-commit.** It is to call the wrapper explicitly
    (fredabood/homelab#2548).
  - **Pre-push config:** pre-push reads the `.gitleaks.toml` at the remote's HEAD, per
    `git ls-remote`, so a pushed commit cannot allowlist itself. Push an allowlist change on its own
    first.
  - **Pre-push needs the remote's HEAD locally.** If it is missing, the push is refused with "fetch
    first".
  - **Kill switch:** `MEMORY_GITLEAKS_CHECK=off` in the environment of the `git` command. The Claude
    Code hook reads its own environment instead. Use it only for the one commit that repairs a broken
    `.gitleaks.toml`.
