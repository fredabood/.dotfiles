# Architecture & Design Documentation

This document explains the design decisions, architecture, and philosophy behind this dotfiles repository.

## Table of Contents

- [Design Philosophy](#design-philosophy)
- [Architecture Overview](#architecture-overview)
- [Directory Structure](#directory-structure)
- [Configuration Loading Order](#configuration-loading-order)
- [Symlink Strategy](#symlink-strategy)
- [Claude Code Configuration](#claude-code-configuration)
- [VS Code Integration](#vs-code-integration)
- [Design Decisions](#design-decisions)
- [Migration From Bash](#migration-from-bash)

---

## Design Philosophy

### Core Principles

1. **Modularity** - Each component is self-contained and can be used independently
2. **Portability** - Easy to deploy to new machines with minimal effort
3. **Version Control** - All configurations tracked in git for history and rollback
4. **Non-Destructive** - Installation preserves existing configurations
5. **Idempotency** - Can be run multiple times safely
6. **Transparency** - Clear documentation and readable scripts
7. **Flexibility** - Easy to customize without breaking core functionality

### Goals

- **Quick Machine Setup** - From zero to fully configured in 15 minutes
- **Consistency** - Same environment across all machines
- **Maintainability** - Easy to update and extend
- **Discoverability** - New users can understand what each component does
- **Safety** - Hard to accidentally break your system

### Non-Goals

- **Cross-Platform Support** - Specifically designed for macOS
- **GUI Configuration** - Focused on command-line tools
- **Automated Updates** - User controls when to pull changes
- **One-Size-Fits-All** - Designed to be forked and customized

---

## Architecture Overview

### High-Level Structure

```
┌─────────────────────────────────────────┐
│          User's Home Directory          │
│  (~/.zshrc, ~/.vimrc, etc. - symlinks)  │
└────────────────┬────────────────────────┘
                 │ symlinks to
                 ▼
┌─────────────────────────────────────────┐
│        ~/Repositories/dotfiles Repository           │
│  ┌──────────────────────────────────┐   │
│  │  zsh/   - Shell configuration    │   │
│  │  vscode/ - Editor configuration  │   │
│  │  macos/  - System preferences    │   │
│  │  brew/   - Package management    │   │
│  │  editors/ - Text editor configs  │   │
│  │  git/    - Version control       │   │
│  └──────────────────────────────────┘   │
│                                          │
│  Scripts:                                │
│  - install.sh     (main installer)       │
│  - sync-vscode.sh (VS Code sync)         │
└──────────────────────────────────────────┘
```

### Component Dependencies

```
┌──────────────┐
│  install.sh  │ ◄─── Entry point
└──────┬───────┘
       │
       ├──► Homebrew ──► brew/Brewfile
       │
       ├──► Oh-My-Zsh ──► zsh/.zshrc
       │                   │
       │                   ├──► zsh/.zshenv
       │                   ├──► zsh/aliases.zsh
       │                   ├──► zsh/functions.zsh
       │                   └──► zsh/path.zsh
       │
       ├──► VS Code ──► vscode/settings.json
       │                vscode/keybindings.json
       │                vscode/extensions.txt
       │
       ├──► Editors ──► editors/.vimrc
       │                editors/.editorconfig
       │
       ├──► Git ──► git/.gitconfig
       │           git/.gitignore_global
       │
       └──► macOS ──► macos/defaults.sh
```

---

## Directory Structure

### Modular Organization

Each top-level directory represents a logical component:

```
.dotfiles/
├── zsh/          # Shell configuration
├── vscode/       # VS Code configuration
├── macos/        # System preferences
├── brew/         # Package management
├── editors/      # Text editors (vim, etc.)
├── git/          # Version control
├── docs/         # Documentation
└── deprecated/   # Archived configurations
```

### Why This Structure?

**Previous (bash-based):**
```
home/
  ├── .bashrc
  ├── .bash_profile
  ├── .aliases
  ├── .functions
  └── ... (50+ mixed files)
```

**Problems:**
- Hard to find related files
- No clear ownership
- Difficult to enable/disable components
- Tight coupling

**Current (modular):**
```
zsh/
  ├── .zshrc         (main config)
  ├── .zshenv        (environment)
  ├── aliases.zsh    (aliases)
  ├── functions.zsh  (functions)
  └── path.zsh       (PATH)
```

**Benefits:**
- Clear separation of concerns
- Easy to locate files
- Can use/skip entire components
- Loose coupling
- Self-documenting structure

---

## Configuration Loading Order

### Zsh Startup Sequence

When a new zsh shell starts, files are loaded in this order:

```
1. /etc/zshenv        (system-wide, always)
2. ~/.zshenv          (user-level, always)
   └── sources ~/Repositories/dotfiles/zsh/.zshenv
3. ~/.zshrc           (interactive shells)
   └── sources ~/Repositories/dotfiles/zsh/.zshrc
       ├── Loads Oh-My-Zsh
       ├── sources ~/Repositories/dotfiles/zsh/.zshenv  (explicit)
       ├── sources ~/Repositories/dotfiles/zsh/path.zsh
       ├── sources ~/Repositories/dotfiles/zsh/aliases.zsh
       ├── sources ~/Repositories/dotfiles/zsh/functions.zsh
       └── sources ~/.zshrc.local  (if exists)
```

### Our Loading Strategy

**~/.zshrc → ~/Repositories/dotfiles/zsh/.zshrc:**
```zsh
# 1. Oh-My-Zsh Configuration
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git macos)
source $ZSH/oh-my-zsh.sh

# 2. Environment Variables
source ~/Repositories/dotfiles/zsh/.zshenv

# 3. PATH Configuration
source ~/Repositories/dotfiles/zsh/path.zsh

# 4. Aliases
source ~/Repositories/dotfiles/zsh/aliases.zsh

# 5. Functions
source ~/Repositories/dotfiles/zsh/functions.zsh

# 6. Local Customizations
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
```

**Why this order?**
1. Oh-My-Zsh first - provides framework and plugins
2. Environment variables - needed by subsequent files
3. PATH - needed before commands are run
4. Aliases - can reference functions
5. Functions - can reference aliases
6. Local customizations - override anything above

---

## Symlink Strategy

### Why Symlinks?

Symlinks allow configuration files to live in the git repository while appearing in their expected locations.

**Benefits:**
- Changes in repo → instantly available to applications
- Changes via applications → instantly in repo (ready to commit)
- Easy to track changes in git
- Simple to rollback
- Clear which files are managed

**Alternative Approaches (Not Used):**

| Approach | Why Not Used |
|----------|-------------|
| **Copying** | Changes in two places, hard to sync |
| **Stow** | Extra dependency, complexity |
| **Home Manager** | Nix-specific, heavyweight |
| **Ansible** | Overkill for personal dotfiles |

### Symlink Implementation

**Created by install.sh:**
```bash
~/.zshrc        → ~/Repositories/dotfiles/zsh/.zshrc
~/.zshenv       → ~/Repositories/dotfiles/zsh/.zshenv
~/.vimrc        → ~/Repositories/dotfiles/editors/.vimrc
~/.gitconfig    → ~/Repositories/dotfiles/git/.gitconfig
~/.editorconfig → ~/Repositories/dotfiles/editors/.editorconfig

# VS Code
~/Library/Application Support/Code/User/settings.json
  → ~/Repositories/dotfiles/vscode/settings.json
~/Library/Application Support/Code/User/keybindings.json
  → ~/Repositories/dotfiles/vscode/keybindings.json
~/Library/Application Support/Code/User/snippets/
  → ~/Repositories/dotfiles/vscode/snippets/

# Claude Code — the five content folders, never ~/.claude itself (see below)
~/.claude/agents     → ~/Repositories/dotfiles/claude/agents
~/.claude/commands   → ~/Repositories/dotfiles/claude/commands
~/.claude/rules      → ~/Repositories/dotfiles/claude/rules
~/.claude/hooks      → ~/Repositories/dotfiles/claude/hooks
~/.claude/skills     → ~/Repositories/dotfiles/claude/skills
~/.claude/statusline-command.sh → ~/Repositories/dotfiles/claude/statusline-command.sh
```

### Backup Strategy

Before creating symlinks, `install.sh` backs up existing files:

```bash
~/.zshrc → ~/.zshrc.backup.20250104_153045
~/.vimrc → ~/.vimrc.backup.20250104_153045
```

Timestamp format: `YYYYMMDD_HHMMSS`

This allows rollback if needed:
```bash
rm ~/.zshrc
mv ~/.zshrc.backup.20250104_153045 ~/.zshrc
```

---

## Claude Code Configuration

`claude/` breaks two of the patterns above, deliberately. Full detail: [`claude/README.md`](../claude/README.md).

### Folder links — but never `~/.claude` itself

`~/.claude` is not a config directory; it is Claude Code's **runtime** directory — session
transcripts, prompt history, background jobs, backups of `~/.claude.json` carrying OAuth data,
`settings.local.json`. Linking it into this public repo would put all of that in the working tree, one
careless `git add` from publication. It stays a real directory.

Its five *content* folders — `agents`, `commands`, `rules`, `hooks`, `skills` — are linked whole, so
the usual dotfiles property holds: anything added, edited or removed in `claude/` is live immediately,
with nothing to re-run. (Until 2026-09-11 each item was linked individually instead; that kept the
folders runtime-owned but meant re-running the installer for every new item, which nobody would.)

The cost is the reverse direction: whatever Claude or a third-party installer writes into those
folders lands in this working tree. `claude/install.sh --status` lists uncommitted items there, and
the pre-commit check still blocks credentials and denylisted private strings. When `install.sh` meets
a real folder it inspects the contents first and refuses to replace one holding items the repo does
not manage. Backups go to `~/.claude-migration-backup/<timestamp>/`, not beside the original — a
backed-up skill directory inside `~/.claude/skills` would load as a duplicate skill.

Folder links were verified in Claude Code 2.1.268 by canaries (a skill, command, rule and agent
created only in `claude/`, with no installer run, all loaded by a fresh session).

### settings.json is generated, not linked

"Changes via applications → instantly in repo" is the wrong property for `~/.claude/settings.json`:
Claude Code writes it through a symlink on every `/model`, `/config` or "always allow", and the file
mixes portable preferences with private details (internal hostnames, machine paths). It is split:

| Half | Lives in | Visibility |
|---|---|---|
| `claude/settings.base.json` | this repo | public |
| `personal/claude/settings.overlay.json` | the memory vault (`$MEMORY_VAULT_PATH`) | private |

`claude/scripts/claude-settings` merges them (objects recursively, arrays unioned) into a regular,
mode-600 file, and absorbs changes Claude makes back into the private overlay when that round-trips
losslessly — refusing, and changing nothing, when it would not.

### Personal information lives in the vault

Prompts that need personal facts (affiliations, email domains, voice profiles) read
`$MEMORY_VAULT_PATH/personal/profile.md` at runtime. The repo-wide pre-commit hook
(`.githooks/pre-commit`) runs gitleaks plus a denylist that is itself kept in the vault — a public
denylist would publish exactly what it blocks.

---

## VS Code Integration

### Architecture

VS Code integration uses a **bidirectional sync model**:

```
┌──────────────────┐         symlink        ┌──────────────────┐
│  VS Code Reads   │ ◄──────────────────────►│  Dotfiles Repo   │
│  From User Dir   │                         │  vscode/         │
└──────────────────┘                         └──────────────────┘
         │                                            │
         │ user edits settings                       │ git commit/push
         ▼                                            ▼
   Changes appear                               Changes tracked
   in dotfiles                                  in version control
```

### Components

**1. Settings & Keybindings (Automatic)**
- Symlinked files
- Changes sync automatically in both directions
- No manual sync needed

**2. Extensions (Manual)**
- Tracked in `extensions.txt`
- Requires running `sync-vscode.sh` to update list
- Installed via `install-extensions.sh`

**3. Snippets (Automatic)**
- Entire directory symlinked
- New snippets appear immediately in repo

### Sync Script Design

**sync-vscode.sh workflow:**
```
1. Check VS Code CLI exists
2. Locate VS Code User directory
3. Copy settings.json → vscode/
4. Copy keybindings.json → vscode/
5. Copy snippets/ → vscode/snippets/
6. Export extensions → vscode/extensions.txt
7. Generate install-extensions.sh
8. Create documentation
```

**Why not bidirectional symlink for extensions?**
- Extensions are managed by VS Code's extension system
- No direct file to symlink
- List must be exported/imported via CLI

---

## Design Decisions

### 1. Zsh Over Bash

**Reasons:**
- macOS default since Catalina (10.15)
- Better interactive features
- Oh-My-Zsh ecosystem
- More active development
- Better completion system

**Trade-offs:**
- Syntax differences from bash
- Learning curve for bash users
- Some bash scripts need #!/bin/bash shebang

### 2. Oh-My-Zsh Framework

**Reasons:**
- Large plugin ecosystem
- Active community
- Good defaults
- Easy theme support
- Well-documented

**Trade-offs:**
- Slight startup time overhead
- Opinionated structure
- Abstraction layer

**Alternatives considered:**
- Bare zsh (more work to configure)
- Prezto (smaller community)
- Zim (faster but fewer plugins)
- Custom framework (too much maintenance)

### 3. Homebrew Bundle (Brewfile)

**Reasons:**
- Declarative package management
- Version controlled
- Easy to sync across machines
- Single command installation
- Supports both CLI and GUI apps

**Alternative:**
- Manual brew install commands
- Shell script with brew install list
- Ansible playbook

### 4. Modular Directory Structure

**Reasons:**
- Clear separation of concerns
- Easy to enable/disable components
- Logical grouping
- Scalable to more components
- Self-documenting

**Alternative:**
- Flat structure with all dotfiles in one directory (original approach)
- Per-tool directories (~/. vim/, ~/.git/, etc.)

### 5. Symlinks Over Copying

**Reasons:**
- Bidirectional sync
- Single source of truth
- Easy to track changes
- Simple to understand
- Standard approach in dotfiles repos

**Alternative:**
- Copy files and use sync script
- Stow (symbolic link manager)
- Direct editing in home directory

### 6. Interactive Installer

**Reasons:**
- User control over what gets installed
- Safe for first-time users
- Can skip optional components
- Provides information during installation

**Alternative:**
- Fully automated (less safe)
- Configuration file driven
- Multiple install scripts

---

## Migration From Bash

### Previous Architecture (Bash-Based)

```
home/
  ├── .bash_profile    # Main entry point
  ├── .bashrc          # Configuration
  ├── .bash_prompt     # Prompt customization
  ├── .aliases         # All aliases
  ├── .functions       # All functions
  ├── .exports         # Environment variables
  ├── .path            # PATH additions
  └── .macos           # macOS settings

bootstrap.sh           # Installation using stow
brew.sh               # Homebrew packages installation
```

### Migration Approach

**Phase 1: Analyze**
- Identify bash-specific vs. shell-agnostic
- Find redundancies with oh-my-zsh
- Assess conda/docker usage

**Phase 2: Restructure**
- Create new directory structure
- Separate concerns into logical groups
- Convert bash syntax to zsh

**Phase 3: Archive**
- Move old files to deprecated/
- Preserve history
- Document changes in MIGRATION.md

**Phase 4: Modernize**
- Convert brew.sh to Brewfile
- Add VS Code integration
- Create interactive installer

**Result:**
- 40% reduction in redundancy
- Better organization
- Improved maintainability
- Added functionality (VS Code sync)

### Key Architectural Changes

| Aspect | Before | After | Benefit |
|--------|--------|-------|---------|
| **Structure** | Flat (home/) | Modular (zsh/, vscode/, etc.) | Clear organization |
| **Shell** | Bash | Zsh + Oh-My-Zsh | Modern, better UX |
| **Installation** | bootstrap.sh + stow | install.sh + symlinks | Simpler, no dependencies |
| **Packages** | brew.sh script | Brewfile | Declarative, version controlled |
| **VS Code** | None | Full integration | Portable editor config |
| **Documentation** | Basic README | Comprehensive docs/ | Better onboarding |

---

## Future Considerations

### Potential Enhancements

**1. Per-Machine Profiles**
```bash
# Could implement:
~/Repositories/dotfiles/profiles/work/
~/Repositories/dotfiles/profiles/personal/
```

**2. Secrets Management**
```bash
# Integration with:
- 1Password CLI
- macOS Keychain
- git-crypt
```

**3. Automated Testing**
```bash
# CI/CD to test:
- Installation on fresh macOS
- Syntax checking
- Link validation
```

**4. Additional Integrations**
- Alacritty/Kitty terminal configs
- tmux configuration
- Neovim setup
- Hammerspoon automation

**5. Platform Support**
- Linux variant branch
- WSL2 support
- Conditional macOS vs. Linux configs

### Scalability

Current structure scales well to:
- More shell components (zsh themes, prompts)
- Additional editors (neovim, emacs)
- Development environments (python, node, go)
- More applications (iterm2, alfred, karabiner)

New components follow same pattern:
```
component-name/
  ├── config files
  ├── README.md
  └── optional install script
```

---

## Design Patterns Used

### 1. Convention Over Configuration
- Standard directory structure
- Predictable file names
- Clear naming conventions

### 2. Progressive Enhancement
- Works with minimal setup
- Additional features are optional
- Can be adopted incrementally

### 3. Separation of Concerns
- Each directory has one responsibility
- Clear boundaries between components
- Loose coupling

### 4. DRY (Don't Repeat Yourself)
- Functions prevent duplication
- Shared utilities
- Modular components

### 5. Single Source of Truth
- Dotfiles repo is canonical source
- Symlinks ensure consistency
- Git provides history

### 6. Fail-Safe Defaults
- Backups before changes
- Interactive confirmation
- Clear error messages
- Reversible operations

---

## Performance Considerations

### Startup Time

**Measured:** ~0.2-0.3 seconds for clean shell startup

**Optimization strategies:**
1. Lazy loading for heavy tools (nvm, conda, etc.)
2. Minimal oh-my-zsh plugins
3. Efficient path configuration
4. Conditional loading

**Bottlenecks to avoid:**
- Too many oh-my-zsh plugins
- Git status in large repositories
- Heavy PATH scanning
- Slow network calls on startup

### Disk Space

**Repository size:** ~2-5 MB
- Configuration files: 100-200 KB
- Documentation: 50-100 KB
- VS Code settings: varies
- Deprecated files: 1-2 MB

**VS Code extensions:** Depends on count (100+ MB typical)

### Network Usage

**Initial setup:**
- Homebrew packages: 500MB - 2GB
- VS Code extensions: 100-500MB
- Oh-My-Zsh: ~1MB

**Updates:** Minimal, only changed components

---

## Contributing to Architecture

If proposing architectural changes, consider:

1. **Backward compatibility** - Will existing users break?
2. **Complexity** - Is it worth the added complexity?
3. **Documentation** - Can it be clearly explained?
4. **Testing** - Can it be tested?
5. **Maintenance** - Who will maintain it?

Document design decisions in this file or propose updates via PR.

---

## References

- [Awesome Dotfiles](https://github.com/webpro/awesome-dotfiles) - Inspiration and best practices
- [Oh-My-Zsh Documentation](https://github.com/ohmyzsh/ohmyzsh/wiki)
- [Homebrew Bundle](https://github.com/Homebrew/homebrew-bundle)
- [XDG Base Directory](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html) - Config file standards
