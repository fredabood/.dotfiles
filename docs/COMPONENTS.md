# Components Documentation

Detailed documentation for each component in the dotfiles repository.

## Table of Contents

- [Zsh Configuration](#zsh-configuration)
- [VS Code Integration](#vs-code-integration)
- [macOS System Preferences](#macos-system-preferences)
- [Homebrew Package Management](#homebrew-package-management)
- [Editor Configurations](#editor-configurations)
- [Git Configuration](#git-configuration)
- [Claude Code Configuration](#claude-code-configuration)
- [Installation Scripts](#installation-scripts)

---

## Zsh Configuration

Location: `zsh/`

### Overview

The zsh configuration is split into multiple files for modularity and maintainability.

### Files

#### `.zshrc`
**Purpose:** Main zsh configuration file
**Location:** `zsh/.zshrc` → symlinked to `~/.zshrc`

**Key Sections:**
1. **Oh-My-Zsh Configuration**
   ```zsh
   export ZSH="$HOME/.oh-my-zsh"
   ZSH_THEME="robbyrussell"
   plugins=(git macos)
   ```

2. **Plugin Loading**
   - Recommended plugins documented in comments
   - Easy to enable/disable

3. **Custom File Sourcing**
   - Sources `.zshenv`, `path.zsh`, `aliases.zsh`, `functions.zsh`
   - Sources `~/.zshrc.local` if it exists

**Customization:**
```bash
# Edit theme
nano ~/.dotfiles/zsh/.zshrc
# Change: ZSH_THEME="agnoster"

# Enable plugins
plugins=(
    git
    macos
    brew
    docker
)
```

#### `.zshenv`
**Purpose:** Environment variables
**Location:** `zsh/.zshenv` → symlinked to `~/.zshenv`

**Contains:**
- `EDITOR` - Default text editor
- `NODE_REPL_*` - Node.js REPL settings
- `PYTHONIOENCODING` - Python encoding
- `HISTSIZE` - History size
- `GPG_TTY` - GPG terminal
- `LANG`, `LC_ALL` - Locale settings
- `VENV_DIR` - Python virtualenv directory

**Why separate file?**
- Loaded by all zsh invocations (not just interactive)
- Used by scripts and programs
- Clean separation of environment vs. interactive config

**Customization:**
```bash
nano ~/.dotfiles/zsh/.zshenv
# Add:
export MY_CUSTOM_VAR="value"
```

#### `aliases.zsh`
**Purpose:** Custom shell aliases
**Location:** `zsh/aliases.zsh`

**Categories:**
1. **Time & Date**
   - `week` - Current week number

2. **Network**
   - `ip` - External IP address
   - `localip` - Local IP address
   - `ips` - All IP addresses

3. **macOS Specific**
   - `cleanup` - Delete .DS_Store files
   - `emptytrash` - Empty trash and logs
   - `show/hide` - Toggle hidden files
   - `hidedesktop/showdesktop` - Toggle desktop icons
   - `afk` - Lock screen

4. **Utilities**
   - `path` - Print PATH entries
   - `h` - Search history
   - `please` - Sudo last command

**Adding Aliases:**
```bash
nano ~/.dotfiles/zsh/aliases.zsh
# Add:
alias myalias="my command"
```

Or use local config:
```bash
echo 'alias myalias="my command"' >> ~/.zshrc.local
```

#### `functions.zsh`
**Purpose:** Custom shell functions
**Location:** `zsh/functions.zsh`

**Key Functions:**

| Function | Purpose | Example |
|----------|---------|---------|
| `mkd()` | Create and enter directory | `mkd ~/test` |
| `cdf()` | CD to Finder location | `cdf` |
| `targz()` | Create compressed archive | `targz mydir` |
| `fs()` | Show file/directory size | `fs ~/Documents` |
| `dataurl()` | Generate data URL | `dataurl image.png` |
| `gz()` | Compare file sizes | `gz file.txt` |
| `digga()` | DNS lookup | `digga example.com` |
| `o()` | Open file/directory | `o .` |
| `tre()` | Enhanced tree view | `tre` |
| `search()` | Recursive grep | `search "pattern"` |

**Adding Functions:**
```bash
nano ~/.dotfiles/zsh/functions.zsh
# Add:
function myfunction() {
    echo "My function"
}
```

#### `path.zsh`
**Purpose:** PATH management
**Location:** `zsh/path.zsh`

**PATH Additions:**
- `~/bin` - User binaries
- `~/.local/bin` - Local binaries
- Homebrew paths (Intel and Apple Silicon)
- Language-specific paths (Java, Python, Node, Ruby, Go, Rust)

**Structure:**
```zsh
# Check if directory exists before adding
[[ -d "$HOME/bin" ]] && export PATH="$HOME/bin:$PATH"
```

**Customization:**
```bash
nano ~/.dotfiles/zsh/path.zsh
# Add:
[[ -d "$HOME/my-tools" ]] && export PATH="$HOME/my-tools:$PATH"
```

---

## VS Code Integration

Location: `vscode/`

### Overview

Complete VS Code configuration management with bidirectional sync.

### Files

#### `settings.json`
**Purpose:** VS Code settings
**Location:** `vscode/settings.json` → symlinked to VS Code User directory

**Contains:**
- Editor preferences (font, size, tab width)
- Language-specific settings
- Extension settings
- Workspace behavior

**Syncing:**
- **Automatic** - Symlinked, changes sync immediately
- Edit in VS Code or directly in file

**Example customization:**
```json
{
    "editor.fontSize": 14,
    "editor.fontFamily": "Fira Code",
    "workbench.colorTheme": "Tokyo Night"
}
```

#### `keybindings.json`
**Purpose:** Custom keyboard shortcuts
**Location:** `vscode/keybindings.json` → symlinked to VS Code User directory

**Syncing:**
- **Automatic** - Symlinked

**Example:**
```json
[
    {
        "key": "cmd+k cmd+d",
        "command": "editor.action.formatDocument"
    }
]
```

#### `extensions.txt`
**Purpose:** List of installed extensions
**Location:** `vscode/extensions.txt`

**Format:**
```
publisher.extension-name
```

**Syncing:**
- **Manual** - Run `./sync-vscode.sh` after installing/removing extensions

**Viewing:**
```bash
cat ~/.dotfiles/vscode/extensions.txt
```

**Installing:**
```bash
cd ~/.dotfiles/vscode
./install-extensions.sh
```

#### `snippets/`
**Purpose:** Custom code snippets
**Location:** `vscode/snippets/` → symlinked to VS Code User snippets

**Structure:**
```
snippets/
├── javascript.json
├── python.json
├── sql.json
└── ...
```

**Syncing:**
- **Automatic** - Entire directory symlinked

**Example snippet:**
```json
{
    "Print to console": {
        "prefix": "log",
        "body": [
            "console.log('$1');",
            "$2"
        ],
        "description": "Log output to console"
    }
}
```

### Scripts

#### `sync-vscode.sh`
**Purpose:** Sync current VS Code config to dotfiles
**Location:** Root directory

**What it syncs:**
1. Settings and keybindings (copies to repo)
2. Snippets (copies to repo)
3. Extensions (exports list)
4. Generates install-extensions.sh

**Usage:**
```bash
./sync-vscode.sh
```

**When to run:**
- After installing/removing extensions
- Before committing VS Code changes
- When setting up the repo for first time

#### `install-extensions.sh`
**Purpose:** Install all extensions from extensions.txt
**Location:** `vscode/install-extensions.sh`

**Auto-generated by:** `sync-vscode.sh`

**Usage:**
```bash
cd vscode/
./install-extensions.sh
```

---

## macOS System Preferences

Location: `macos/`

### Overview

Automates macOS system preferences configuration using the `defaults` command.

### Files

#### `defaults.sh`
**Purpose:** Configure macOS system settings
**Location:** `macos/defaults.sh`

**Categories:**

1. **General UI/UX**
   - Screenshot location
   - Finder path/status bars
   - Standby delay
   - Transparency settings

2. **Trackpad & Mouse**
   - Tap to click
   - Natural scrolling
   - Tracking speed

3. **Keyboard**
   - Key repeat rate
   - Language settings
   - Disable press-and-hold

4. **Finder**
   - Show hidden files
   - Show file extensions
   - Default view style
   - New window location

5. **Dock**
   - Icon size
   - Auto-hide behavior
   - Animation speed

6. **Safari**
   - Default page
   - Developer menu
   - Privacy settings

7. **Security**
   - Screen lock
   - FileVault

**Usage:**
```bash
# Review first!
less ~/.dotfiles/macos/defaults.sh

# Apply settings
./macos/defaults.sh
```

**⚠️ Important:**
- Some settings require logout/restart
- Review script before running
- Settings are system-wide
- Can affect other users

**Reverting Changes:**
```bash
# Example: Restore default Dock size
defaults write com.apple.dock tilesize -int 48
killall Dock
```

**Customization:**
```bash
nano ~/.dotfiles/macos/defaults.sh
# Add your preferred settings
```

**Finding Settings:**
```bash
# Current setting
defaults read com.apple.finder ShowPathBar

# Change setting
defaults write com.apple.finder ShowPathBar -bool true
killall Finder
```

---

## Homebrew Package Management

Location: `brew/`

### Overview

Declarative package management using Homebrew Bundle.

### Files

#### `Brewfile`
**Purpose:** Define all Homebrew packages and casks
**Location:** `brew/Brewfile`

**Structure:**
```ruby
# Taps
tap "homebrew/cask"
tap "homebrew/cask-fonts"

# CLI tools
brew "git"
brew "vim"
brew "wget"

# GUI applications
cask "visual-studio-code"
cask "docker"

# Fonts
cask "font-fira-code"
```

**Categories:**

1. **Core Utilities**
   - coreutils, moreutils, findutils, gnu-sed

2. **Network Tools**
   - wget, curl, openssh

3. **Development**
   - git, vim, tmux, jq

4. **Applications**
   - VS Code, Docker

5. **Optional** (commented out)
   - Programming languages
   - Databases
   - Cloud CLIs

**Installation:**
```bash
cd ~/.dotfiles
brew bundle --file=brew/Brewfile
```

**Adding Packages:**
```bash
nano ~/.dotfiles/brew/Brewfile
# Add:
brew "package-name"
cask "app-name"

# Install
brew bundle --file=brew/Brewfile
```

**Cleaning Up:**
```bash
# Remove packages not in Brewfile
brew bundle cleanup --file=brew/Brewfile
```

**Checking Status:**
```bash
# What's installed vs. Brewfile
brew bundle check --file=brew/Brewfile
```

**Generating from Current:**
```bash
# Dump current installations to Brewfile
brew bundle dump --file=brew/Brewfile.new
```

---

## Editor Configurations

Location: `editors/`

### Overview

Configuration files for text editors.

### Files

#### `.vimrc`
**Purpose:** Vim configuration
**Location:** `editors/.vimrc` → symlinked to `~/.vimrc`

**Key Features:**
1. **Appearance**
   - Solarized Dark color scheme
   - Line numbers
   - Syntax highlighting
   - Cursor line highlight

2. **Behavior**
   - UTF-8 encoding
   - Wildmenu completion
   - Mouse support
   - No error bells

3. **File Handling**
   - Centralized backups, swaps, undo
   - No BOM, no trailing newlines

4. **Key Mappings**
   - Leader key: `,`
   - `,ss` - Strip whitespace
   - `,W` - Save as root

5. **File Types**
   - JSON syntax
   - Markdown support

**Directories Created:**
```bash
~/.vim/backups/
~/.vim/swaps/
~/.vim/undo/
```

**Customization:**
```bash
nano ~/.dotfiles/editors/.vimrc
```

#### `.editorconfig`
**Purpose:** Universal editor configuration
**Location:** `editors/.editorconfig` → symlinked to `~/.editorconfig`

**Settings:**
```ini
root = true

[*]
charset = utf-8
indent_style = tab
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true
```

**Supported by:**
- VS Code
- Sublime Text
- Atom
- IntelliJ IDEA
- Many others

**Why use it?**
- Consistent formatting across editors
- Team collaboration
- Language-agnostic

---

## Git Configuration

Location: `git/`

### Overview

Git settings and global ignore patterns.

### Files

#### `.gitconfig`
**Purpose:** Git configuration
**Location:** `git/.gitconfig` → symlinked to `~/.gitconfig`

**Key Sections:**
1. **User** - Name and email
2. **Core** - Editor, excludesfile
3. **Color** - Syntax highlighting
4. **Aliases** - Shortcuts
5. **Push/Pull** - Behavior

**Example content:**
```ini
[user]
    name = Your Name
    email = your.email@example.com

[core]
    editor = vim
    excludesfile = ~/.gitignore_global

[alias]
    st = status
    co = checkout
    br = branch
    ci = commit
```

**Customization:**
```bash
# Via command
git config --global user.name "Your Name"

# Or edit directly
nano ~/.dotfiles/git/.gitconfig
```

#### `.gitignore_global`
**Purpose:** Global gitignore patterns
**Location:** `git/.gitignore_global` → symlinked to `~/.gitignore_global`

**Common Patterns:**
```
# macOS
.DS_Store
.AppleDouble

# Editors
.vscode/
.idea/
*.swp

# Languages
__pycache__/
node_modules/
*.pyc
```

**Adding Patterns:**
```bash
nano ~/.dotfiles/git/.gitignore_global
```

**Verify It's Active:**
```bash
git config --global core.excludesfile
# Should show: /Users/yourname/.gitignore_global
```

---

## Claude Code Configuration

Location: `claude/` — full reference in [`claude/README.md`](../claude/README.md).

### Overview

Shared Claude Code config — agents, slash commands, rules, hooks, skills and the status line — whose
five content folders are linked whole into `~/.claude` (new items are live immediately), plus the
public half of `~/.claude/settings.json`. Personal facts and private settings live in the memory
vault (`$MEMORY_VAULT_PATH/personal/`), never here.

### Files

| Path | Installs as | Notes |
|---|---|---|
| `claude/agents/`, `commands/`, `rules/` | `~/.claude/<folder>` (folder symlink) | add a `.md` and it is live |
| `claude/hooks/` | `~/.claude/hooks` (folder symlink) | registered in `settings.base.json` via `$HOME/.claude/hooks/...`; `claude-settings-sync.sh` keeps settings in sync on every SessionStart |
| `claude/skills/` | `~/.claude/skills` (folder symlink) | one directory per skill |
| `claude/statusline-command.sh` | `~/.claude/statusline-command.sh` (symlink) | |
| `claude/settings.base.json` | merged into `~/.claude/settings.json` (generated) | public preferences, permissions, hooks |
| `claude/install.sh` | — | `--status`, `--dry-run`, `--materialize` |
| `claude/scripts/claude-settings` | — | `status`, `diff`, `apply`, `absorb`, `sync` |
| `claude/scripts/check-public.sh` | — | gitleaks + vault denylist; the repo pre-commit hook |
| `claude/tests/install.test.sh` | — | fake-HOME test suite |

### Usage

```bash
~/.dotfiles/claude/install.sh --status          # link health + settings state
~/.dotfiles/claude/scripts/claude-settings diff  # live settings vs base + overlay
bash ~/.dotfiles/claude/tests/install.test.sh    # after changing the scripts
```

### Dependencies

`jq` and `gitleaks` (both in the Brewfile), and — for the private overlay, profile and denylist —
the memory vault cloned at `~/Repositories/memory` (`MEMORY_VAULT_PATH`, exported in `zsh/.zshenv`).

---

## Installation Scripts

### `install.sh`
**Purpose:** Main installation script
**Location:** Root directory

**Features:**
- Interactive prompts
- Backup existing configs
- Install Homebrew (if needed)
- Install Oh-My-Zsh (if needed)
- Install packages from Brewfile
- Install oh-my-zsh plugins
- Create symlinks
- Setup VS Code
- Optionally apply macOS settings

**Phases:**
1. Pre-flight checks
2. Homebrew installation
3. Oh-My-Zsh installation
4. Package installation
5. Plugin installation
6. Configuration linking
7. VS Code setup
8. macOS preferences

**Safety Features:**
- Timestamped backups
- User confirmation prompts
- Detailed logging
- Error handling

**Usage:**
```bash
./install.sh
```

**Rerunning:**
Safe to run multiple times. Will:
- Skip already installed components
- Recreate symlinks if needed
- Backup before overwriting

### `sync-vscode.sh`
**Purpose:** Sync VS Code config to repository
**Location:** Root directory

**Process:**
1. Verify VS Code installation
2. Check VS Code settings directory
3. Copy settings.json
4. Copy keybindings.json
5. Copy snippets
6. Export extensions list
7. Generate install-extensions.sh
8. Create documentation

**Usage:**
```bash
./sync-vscode.sh
```

**When to run:**
- First time setup
- After installing extensions
- Before committing VS Code changes
- Periodically to keep in sync

---

## Component Interaction

### Startup Flow

```
User opens terminal
  ↓
zsh starts
  ↓
Sources ~/.zshrc (symlink to ~/.dotfiles/zsh/.zshrc)
  ↓
Loads Oh-My-Zsh
  ↓
Sources ~/.dotfiles/zsh/.zshenv (environment)
  ↓
Sources ~/.dotfiles/zsh/path.zsh (PATH)
  ↓
Sources ~/.dotfiles/zsh/aliases.zsh (aliases)
  ↓
Sources ~/.dotfiles/zsh/functions.zsh (functions)
  ↓
Sources ~/.zshrc.local (if exists, machine-specific)
  ↓
Ready for user input
```

### Installation Flow

```
./install.sh
  ↓
Check/Install Homebrew
  ↓
Check/Install Oh-My-Zsh
  ↓
brew bundle (install packages)
  ↓
Install zsh plugins
  ↓
Create symlinks:
  - zsh configs
  - editor configs
  - git configs
  - VS Code configs
  ↓
Optional: Apply macOS settings
  ↓
Complete
```

### VS Code Sync Flow

```
./sync-vscode.sh
  ↓
Find VS Code User directory
  ↓
Copy settings.json → vscode/
  ↓
Copy keybindings.json → vscode/
  ↓
Copy snippets/ → vscode/snippets/
  ↓
Export extensions → vscode/extensions.txt
  ↓
Generate install-extensions.sh
  ↓
Create/update README
  ↓
Ready to commit
```

---

## Maintenance

### Regular Tasks

1. **Update packages:**
   ```bash
   cd ~/.dotfiles
   brew bundle --file=brew/Brewfile
   ```

2. **Sync VS Code:**
   ```bash
   ./sync-vscode.sh
   git add vscode/
   git commit -m "Update VS Code config"
   ```

3. **Update oh-my-zsh:**
   ```bash
   omz update
   ```

4. **Commit changes:**
   ```bash
   git add .
   git commit -m "Update configurations"
   git push
   ```

### Health Checks

```bash
# Verify symlinks
ls -la ~ | grep "\.dotfiles"

# Check zsh config loads
zsh -n ~/.zshrc

# Test aliases
alias | grep cleanup

# Test functions
type mkd
```

---

## Component Dependencies

```
install.sh
  ├── Requires: git, bash/zsh
  ├── Installs: Homebrew
  │   └── Installs: packages from Brewfile
  ├── Installs: Oh-My-Zsh
  │   └── Optional: zsh plugins
  └── Creates: symlinks

zsh configuration
  ├── Requires: Oh-My-Zsh
  ├── Sources: .zshenv, path.zsh, aliases.zsh, functions.zsh
  └── Optional: .zshrc.local

VS Code sync
  ├── Requires: VS Code CLI (`code` command)
  ├── Reads: ~/Library/Application Support/Code/User/
  └── Writes: vscode/ directory

macOS defaults
  ├── Requires: macOS, sudo
  └── Affects: System-wide settings
```

---

## Next Steps

- **Customize** - See [Customization Guide](CUSTOMIZATION.md)
- **Troubleshoot** - See [Troubleshooting Guide](TROUBLESHOOTING.md)
- **FAQ** - See [FAQ](FAQ.md)
- **Architecture** - See [Architecture Documentation](ARCHITECTURE.md)
