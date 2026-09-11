# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Claude Code configuration** (`claude/`), moved here from the standalone `fredabood/.claude` repo
  (copied without its history). `claude/install.sh` links the five content folders (agents, commands,
  rules, hooks, skills) and the status line into `~/.claude` — never the whole runtime directory.
- `claude/scripts/claude-settings`: generates `~/.claude/settings.json` from the public
  `claude/settings.base.json` plus a private overlay in the memory vault, and absorbs changes Claude
  Code makes back into the overlay when that is lossless.
- `claude/hooks/claude-settings-sync.sh`, a `SessionStart` hook that runs that sync automatically
  (fast no-op when nothing changed), commits the absorbed overlay in the vault, and warns in-session
  only when sync refuses — so `/config` and `/model` changes need no manual step.
- `.githooks/pre-commit` → `claude/scripts/check-public.sh`: gitleaks plus a private denylist on
  every staged change. `install.sh` enables it (`core.hooksPath`). `gitleaks` added to the Brewfile.
- `MEMORY_VAULT_PATH` export in `zsh/.zshenv`.

### Changed
- `~/.claude/{agents,commands,rules,hooks,skills}` are now **folder** links instead of one link per
  item, so anything added to `claude/` is live immediately with nothing to re-run. `install.sh`
  migrates the per-item layout, refuses to hide items the repo does not manage, and `--status` lists
  uncommitted items in the linked folders. The SessionStart sync hook now resolves its package
  through a folder link (it would otherwise have stopped syncing silently) and warns instead of
  exiting quietly if it cannot.
- Personal information (affiliations, email domains, voice profiles, 1Password vault name) removed
  from the shared prompts; they read `$MEMORY_VAULT_PATH/personal/profile.md` at runtime instead.

## [2.0.0] - 2025-01-04

### Major Refactor - Zsh Migration

Complete modernization of the dotfiles repository from bash to zsh with significant improvements.

### Added
- **Zsh Configuration**
  - Modular zsh configuration split into multiple files
  - Integration with oh-my-zsh framework
  - `zsh/.zshrc` - Main configuration file
  - `zsh/.zshenv` - Environment variables
  - `zsh/aliases.zsh` - Custom aliases
  - `zsh/functions.zsh` - Shell functions
  - `zsh/path.zsh` - PATH management

- **VS Code Integration**
  - Complete VS Code configuration management
  - `vscode/settings.json` - Editor settings
  - `vscode/keybindings.json` - Custom keybindings
  - `vscode/extensions.txt` - Extensions list (33 extensions)
  - `vscode/snippets/` - Code snippets directory
  - `sync-vscode.sh` - Bidirectional sync script
  - `vscode/install-extensions.sh` - Auto-generated extension installer

- **Package Management**
  - `brew/Brewfile` - Declarative Homebrew package management
  - Replaced bash script with modern Brewfile format

- **Documentation**
  - `docs/SETUP.md` - Comprehensive installation guide
  - `docs/TROUBLESHOOTING.md` - Common issues and solutions
  - `docs/FAQ.md` - Frequently asked questions
  - `docs/ARCHITECTURE.md` - Design and architecture documentation
  - `docs/COMPONENTS.md` - Detailed component documentation
  - `docs/CUSTOMIZATION.md` - Customization guide
  - `MIGRATION.md` - Migration summary from bash to zsh
  - Completely rewritten `README.md`

- **Installation**
  - `install.sh` - New interactive installation script
  - Automatic backup mechanism for existing configs
  - Safe, idempotent installation process
  - Support for oh-my-zsh plugin installation

- **Organization**
  - `git/` - Git configuration directory
  - `editors/` - Editor configurations (vim, editorconfig)
  - `macos/` - macOS system preferences
  - `deprecated/` - Archived old configurations

### Changed
- **Directory Structure**
  - Reorganized from flat `home/` directory to modular structure
  - Separated concerns into logical directories
  - Improved discoverability and maintainability

- **Shell Configuration**
  - Migrated from bash to zsh
  - Integrated with oh-my-zsh for better plugin ecosystem
  - Modularized configuration for easier management

- **Package Management**
  - Converted `brew.sh` to `brew/Brewfile`
  - Declarative package definitions
  - Better version control for packages

### Removed
- **Redundant Components**
  - Removed ~40% of redundant functionality now provided by oh-my-zsh
  - Navigation aliases (now in oh-my-zsh)
  - Git aliases (oh-my-zsh git plugin provides 197 aliases)
  - Bash completion (replaced by zsh completion)

### Deprecated
- **Bash Configurations** (moved to `deprecated/bash/`)
  - `.bash_profile`
  - `.bashrc`
  - `.bash_prompt`

- **Conda Infrastructure** (moved to `deprecated/conda/`)
  - `conda.sh`
  - `.condarc`
  - `.requirements.txt`
  - `envs/` directory

- **Docker Setup** (moved to `deprecated/docker/`)
  - `Dockerfile`

- **Installation Scripts**
  - `bootstrap.sh` (replaced by `install.sh`)
  - `brew.sh` (replaced by `brew/Brewfile`)

### Fixed
- Broken references to GNU coreutils (`gls`) that weren't installed
- Dependency on `stow` which wasn't required
- Bash-specific syntax throughout codebase

### Migration Notes
- All original files preserved in `deprecated/` directory
- Symlink-based approach for easy rollback
- Zero data loss during migration
- Backward compatibility maintained through archived configs

---

## [1.0.0] - Pre-2025

### Initial Release - Bash-Based Dotfiles

Original bash-focused dotfiles forked from Mathias Bynens' dotfiles.

### Included
- **Bash Configuration**
  - `.bash_profile` - Main bash configuration
  - `.bashrc` - Bash runtime configuration
  - `.bash_prompt` - Custom bash prompt
  - `.aliases` - Shell aliases
  - `.functions` - Shell functions
  - `.exports` - Environment variables
  - `.path` - PATH configuration

- **Development Tools**
  - `brew.sh` - Homebrew package installation script
  - `conda.sh` - Miniconda installation and setup
  - Conda environment configurations (py27.yml, py37.yml)

- **Editor Configurations**
  - `.vimrc` - Vim configuration
  - `.gvimrc` - GVim configuration
  - `.editorconfig` - Universal editor configuration

- **System Configurations**
  - `.macos` - Comprehensive macOS system preferences
  - `.gitconfig` - Git configuration
  - `.gitignore` - Global git ignore patterns
  - `.curlrc` - Curl settings
  - `.wgetrc` - Wget settings
  - `.inputrc` - Readline configuration
  - `.screenrc` - GNU Screen configuration

- **Installation**
  - `bootstrap.sh` - Installation script using stow
  - Required GNU Stow for symlinking

- **Docker Support**
  - `Dockerfile` - Containerized development environment
  - Ubuntu + Miniconda + dotfiles setup

### Features
- Forked from [Mathias Bynens' dotfiles](https://github.com/mathiasbynens/dotfiles)
- Used stow for symlink management
- Comprehensive bash environment setup
- Extensive macOS customization
- Conda-based Python environment management

---

## Version History Summary

| Version | Date | Key Changes |
|---------|------|-------------|
| 2.0.0 | 2025-01-04 | Complete zsh migration, VS Code integration, modular structure |
| 1.0.0 | Pre-2025 | Original bash-based dotfiles |

---

## Upgrade Path

### From 1.x to 2.x

**Not a typical upgrade** - This is a complete architectural change. Recommended approach:

**Option 1: Fresh Install (Recommended)**
```bash
# Backup your old dotfiles
mv ~/.dotfiles ~/.dotfiles.old

# Clone new version
git clone https://github.com/fredabood/.dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./install.sh
```

**Option 2: Pull Changes (For Git Users)**
```bash
cd ~/.dotfiles
git pull origin master

# Review changes
git log --oneline -20

# Install with new structure
./install.sh
```

**What Happens to Old Config:**
- Old files archived in `deprecated/`
- Original functionality preserved
- Can reference old configs in `deprecated/bash/`
- Bash configs can be manually restored if needed

---

## Future Roadmap

### Planned Features

**2.1.0**
- [ ] Enhanced terminal themes support (Powerlevel10k configuration)
- [x] iTerm2 configuration integration
- [ ] tmux configuration
- [ ] Neovim setup alongside Vim

**2.2.0**
- [ ] Per-machine profile system
- [ ] Secrets management integration (1Password, Keychain)
- [ ] CI/CD testing pipeline

**2.3.0**
- [ ] Linux variant branch
- [ ] WSL2 support
- [ ] Conditional cross-platform configs

**3.0.0**
- [ ] Complete rewrite with version management
- [ ] Plugin system for optional components
- [ ] GUI installer application
- [ ] Automated update system

### Considering
- Alacritty/Kitty terminal configuration
- Hammerspoon automation scripts
- Karabiner-Elements key remapping
- Alfred workflows
- Docker development environment templates

---

## Breaking Changes

### 2.0.0

**Shell Change:**
- Bash → Zsh: Some bash-specific scripts may not work
- Environment variable syntax differences
- Array syntax differences

**Directory Structure:**
- `home/` → Multiple directories (`zsh/`, `vscode/`, etc.)
- Symlinks change from `home/.file` to `component/.file`

**Installation:**
- `bootstrap.sh` + stow → `install.sh` + native symlinking
- No longer requires GNU Stow

**Package Management:**
- `brew.sh` script → `brew/Brewfile`
- Different syntax for package definitions

**Removed Features:**
- Conda auto-installation
- Docker containerized environment
- Bash-specific customizations

**Migration Required:**
- Re-run installation script
- Update any personal scripts referencing old structure
- Review and adopt new zsh configuration
- Sync VS Code settings with new system

---

## Contributing

When contributing, please:
1. Update this CHANGELOG with your changes
2. Follow [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format
3. Categorize changes as: Added, Changed, Deprecated, Removed, Fixed, Security
4. Include version number and date
5. Document breaking changes clearly

---

## Acknowledgments

### Version 2.0
- Migrated and modernized by fredabood
- Inspired by modern dotfiles practices
- Oh-My-Zsh framework integration
- VS Code settings sync pattern

### Version 1.0
- Originally forked from [Mathias Bynens' dotfiles](https://github.com/mathiasbynens/dotfiles)
- Stow integration inspired by [Cody Reichert](https://github.com/CodyReichert/dotfiles)
- Conda setup based on [Hamel Husain's Docker tutorial](https://github.com/hamelsmu/Docker_Tutorial)

---

## License

MIT License - See [LICENSE-MIT.txt](LICENSE-MIT.txt)
