# Worktrees — inside the repo

Git worktrees live **inside the repository they belong to**, at `<repo>/.claude/worktrees/<name>`.
Never create a sibling `../<repo>-worktrees/` or `~/<repo>-worktrees/` directory: they pile up
beside every repo and outlive the work that made them.

- **Prefer `EnterWorktree`** (or `claude --worktree <name>`). It already uses this path and copies
  the files a repo lists in `.worktreeinclude` (typically `.env`).
- **Need a specific branch name?** Create the worktree yourself, then enter it:
  `git worktree add .claude/worktrees/<name> -b <branch> origin/<default-branch>`, then
  `EnterWorktree` with `path`. Copy `.env` by hand — `.worktreeinclude` only applies to worktrees
  Claude Code creates.
- `.claude/worktrees/` is ignored globally (`~/.gitignore`). A repo whose linters or formatters walk
  dot-directories also needs it in its own ignore config — CI never sees the global file.
- Remove a worktree with `git worktree remove` once its branch has landed.
- A repo's own `CLAUDE.md` or rules win where they say more (branch naming, gates, merge flow).
