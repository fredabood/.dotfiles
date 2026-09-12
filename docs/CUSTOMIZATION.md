# Customization Guide

How to customize and personalize your dotfiles.

## Table of Contents

- [Quick Customization](#quick-customization)
- [Zsh Customization](#zsh-customization)
- [VS Code Customization](#vs-code-customization)
- [Adding Packages](#adding-packages)
- [macOS Settings](#macos-settings)
- [Machine-Specific Settings](#machine-specific-settings)
- [Advanced Customization](#advanced-customization)

---

## Quick Customization

### Most Common Customizations

**1. Change zsh theme:**
```bash
nano ~/Repositories/dotfiles/zsh/.zshrc
# Change: ZSH_THEME="robbyrussell" to your preferred theme
```

**2. Add aliases:**
```bash
# For all machines (tracked in git):
nano ~/Repositories/dotfiles/zsh/aliases.zsh

# For this machine only:
echo 'alias myalias="command"' >> ~/.zshrc.local
```

**3. Change default editor:**
```bash
nano ~/Repositories/dotfiles/zsh/.zshenv
# Change: export EDITOR='vim' to your preferred editor
```

**4. Add Homebrew packages:**
```bash
nano ~/Repositories/dotfiles/brew/Brewfile
# Add: brew "package-name"
brew bundle --file=~/Repositories/dotfiles/brew/Brewfile
```

---

## Zsh Customization

### Themes

**Popular themes:**
- `robbyrussell` - Default, simple
- `agnoster` - Powerline-style, shows git info
- `powerlevel10k/powerlevel10k` - Highly customizable

**Install Powerlevel10k:**
```bash
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
```

**Set in .zshrc:**
```zsh
ZSH_THEME="powerlevel10k/powerlevel10k"
```

**Configure:**
```bash
p10k configure
```

### Plugins

**Enable built-in plugins:**
```bash
nano ~/Repositories/dotfiles/zsh/.zshrc
```

Add to plugins array:
```zsh
plugins=(
    git          # Git aliases
    macos        # macOS specific
    brew         # Homebrew completion
    docker       # Docker completion
    z            # Directory jumping
    sudo         # Press ESC twice for sudo
    copyfile     # Copy file contents
    copybuffer   # Copy terminal buffer
)
```

**Install custom plugins:**
```bash
# zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

# zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-syntax-highlighting ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
```

Add to plugins array:
```zsh
plugins=(
    ...
    zsh-autosuggestions
    zsh-syntax-highlighting
)
```

### Custom Aliases

**Add to aliases.zsh:**
```bash
nano ~/Repositories/dotfiles/zsh/aliases.zsh
```

Examples:
```zsh
# Development
alias dev="cd ~/Development"
alias proj="cd ~/Projects"

# Git shortcuts (if not using git plugin)
alias gs="git status"
alias gp="git push"
alias gl="git pull"

# Docker
alias dps="docker ps"
alias dpa="docker ps -a"
alias di="docker images"

# Python
alias py="python3"
alias pip="pip3"
alias venv="python3 -m venv"

# Quick edits
alias zshconfig="nano ~/Repositories/dotfiles/zsh/.zshrc"
alias aliasconfig="nano ~/Repositories/dotfiles/zsh/aliases.zsh"
```

### Custom Functions

**Add to functions.zsh:**
```bash
nano ~/Repositories/dotfiles/zsh/functions.zsh
```

Examples:
```zsh
# Create and enter project directory with git init
function newproject() {
    mkd "$1"
    git init
    echo "# $1" > README.md
    touch .gitignore
}

# Quick backup
function backup() {
    cp "$1" "$1.backup.$(date +%Y%m%d_%H%M%S)"
}

# Extract any archive
function extract() {
    if [ -f "$1" ]; then
        case "$1" in
            *.tar.bz2) tar xjf "$1" ;;
            *.tar.gz)  tar xzf "$1" ;;
            *.bz2)     bunzip2 "$1" ;;
            *.gz)      gunzip "$1"  ;;
            *.tar)     tar xf "$1"  ;;
            *.zip)     unzip "$1"   ;;
            *) echo "Unknown archive format" ;;
        esac
    fi
}

# Weather in terminal
function weather() {
    curl "wttr.in/${1:-}"
}
```

### PATH Customization

**Add to path.zsh:**
```bash
nano ~/Repositories/dotfiles/zsh/path.zsh
```

Examples:
```zsh
# Custom tools
[[ -d "$HOME/my-tools" ]] && export PATH="$HOME/my-tools:$PATH"

# Programming language managers
[[ -d "$HOME/.pyenv/bin" ]] && export PATH="$HOME/.pyenv/bin:$PATH"
eval "$(pyenv init -)"

# Project-specific binaries
[[ -d "$HOME/Projects/bin" ]] && export PATH="$HOME/Projects/bin:$PATH"
```

### Environment Variables

**Add to .zshenv:**
```bash
nano ~/Repositories/dotfiles/zsh/.zshenv
```

Examples:
```zsh
# Development
export DEVELOPMENT_DIR="$HOME/Development"
export PROJECTS_DIR="$HOME/Projects"

# API keys (use carefully, consider keychain instead)
# export API_KEY="your-key-here"  # Don't commit secrets!

# Language-specific
export GOPATH="$HOME/go"
export RUSTUP_HOME="$HOME/.rustup"
export CARGO_HOME="$HOME/.cargo"

# Custom settings
export BROWSER="open"
export PAGER="less"
```

---

## VS Code Customization

### Settings

**Edit settings directly:**
```bash
nano ~/Repositories/dotfiles/vscode/settings.json
```

**Common customizations:**
```json
{
    "editor.fontSize": 14,
    "editor.fontFamily": "Fira Code, Menlo, Monaco, 'Courier New'",
    "editor.fontLigatures": true,
    "editor.tabSize": 2,
    "editor.formatOnSave": true,

    "workbench.colorTheme": "Tokyo Night",
    "workbench.iconTheme": "material-icon-theme",

    "terminal.integrated.fontSize": 12,
    "terminal.integrated.fontFamily": "MesloLGS NF",

    "files.autoSave": "onFocusChange",
    "files.trimTrailingWhitespace": true
}
```

Changes appear immediately in VS Code (symlinked).

### Extensions

**Add extensions:**
1. Install in VS Code GUI or CLI
   ```bash
   code --install-extension publisher.extension
   ```

2. Sync to dotfiles
   ```bash
   ./sync-vscode.sh
   git add vscode/
   git commit -m "Add new extensions"
   ```

**Recommended extensions:**
- `dbaeumer.vscode-eslint` - JavaScript linting
- `esbenp.prettier-vscode` - Code formatting
- `eamodio.gitlens` - Git superpowers
- `vscodevim.vim` - Vim keybindings
- `ms-python.python` - Python support
- `ms-vscode.sublime-keybindings` - Sublime Text keybindings

### Keybindings

**Edit keybindings:**
```bash
nano ~/Repositories/dotfiles/vscode/keybindings.json
```

**Examples:**
```json
[
    {
        "key": "cmd+shift+f",
        "command": "workbench.action.findInFiles"
    },
    {
        "key": "cmd+k cmd+d",
        "command": "editor.action.formatDocument"
    },
    {
        "key": "ctrl+`",
        "command": "workbench.action.terminal.toggleTerminal"
    }
]
```

### Snippets

**Create snippet file:**
```bash
nano ~/Repositories/dotfiles/vscode/snippets/language.json
```

**Example (JavaScript):**
```json
{
    "Console Log": {
        "prefix": "log",
        "body": [
            "console.log('$1:', $1);",
            "$2"
        ],
        "description": "Log with label"
    },
    "Arrow Function": {
        "prefix": "af",
        "body": [
            "const ${1:name} = (${2:params}) => {",
            "  $3",
            "};"
        ]
    }
}
```

---

## Adding Packages

### Homebrew Packages

**Add CLI tools:**
```bash
nano ~/Repositories/dotfiles/brew/Brewfile
```

Add:
```ruby
# CLI Tools
brew "htop"        # Process viewer
brew "tree"        # Directory tree
brew "bat"         # Better cat
brew "ripgrep"     # Better grep
brew "fd"          # Better find
brew "exa"         # Better ls
```

**Add GUI applications:**
```ruby
# Applications
cask "iterm2"
cask "alfred"
cask "rectangle"
cask "spotify"
```

**Install:**
```bash
brew bundle --file=~/Repositories/dotfiles/brew/Brewfile
```

### Programming Languages

**Via Homebrew:**
```ruby
brew "python"
brew "node"
brew "go"
brew "rust"
```

**Via Version Managers (recommended):**
```bash
# pyenv (Python)
brew "pyenv"
# Add to path.zsh:
# eval "$(pyenv init -)"

# nvm (Node.js)
brew "nvm"
# Add to .zshrc.local:
# export NVM_DIR="$HOME/.nvm"
# [ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"

# rbenv (Ruby)
brew "rbenv"
# Add to path.zsh:
# eval "$(rbenv init -)"
```

---

## macOS Settings

### Customize defaults.sh

**Edit macOS settings:**
```bash
nano ~/Repositories/dotfiles/macos/defaults.sh
```

**Common customizations:**

**Dock:**
```bash
# Dock size
defaults write com.apple.dock tilesize -int 50

# Auto-hide delay
defaults write com.apple.dock autohide-delay -float 0.5
```

**Finder:**
```bash
# Show hidden files
defaults write com.apple.finder AppleShowAllFiles -bool true

# Default view (list view)
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"
```

**Screenshots:**
```bash
# Screenshot location
defaults write com.apple.screencapture location -string "${HOME}/Pictures/Screenshots"

# Screenshot format
defaults write com.apple.screencapture type -string "png"
```

**Keyboard:**
```bash
# Key repeat rate
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15
```

**Apply changes:**
```bash
./macos/defaults.sh
```

---

## Machine-Specific Settings

### Using .zshrc.local

Create `~/.zshrc.local` for machine-specific settings not tracked in git:

```bash
touch ~/.zshrc.local
nano ~/.zshrc.local
```

**Examples:**

**Work laptop:**
```zsh
# Work-specific paths
export WORK_DIR="$HOME/work"
export COMPANY_REPO="$HOME/work/company-repo"

# Work aliases
alias work="cd $WORK_DIR"
alias repo="cd $COMPANY_REPO"
alias vpn="sudo openconnect vpn.company.com"

# Work environment
export COMPANY_ENV=production
export AWS_PROFILE=work

# Work git config (override global)
git config --global user.email "work@company.com"
```

**Personal desktop:**
```zsh
# Personal projects
export PERSONAL_DIR="$HOME/Personal"
alias personal="cd $PERSONAL_DIR"

# Home server
export NAS_IP="192.168.1.100"
alias nas="ssh user@$NAS_IP"
alias backup="rsync -av $HOME/Documents user@$NAS_IP:/backup"

# Media paths
export MUSIC_DIR="/Volumes/Music"
export VIDEO_DIR="/Volumes/Videos"
```

### Conditional Configuration

**Based on hostname:**
```zsh
# In ~/.zshrc.local
if [[ $(hostname) == "work-macbook"* ]]; then
    # Work settings
    export WORK_MODE=true
elif [[ $(hostname) == "personal-imac"* ]]; then
    # Personal settings
    export PERSONAL_MODE=true
fi
```

**Based on directory:**
```zsh
# Different git email per directory
[[ $(pwd) =~ "/work/" ]] && git config user.email "work@company.com"
```

---

## Advanced Customization

### Custom Oh-My-Zsh Theme

**Create custom theme:**
```bash
mkdir -p ~/.oh-my-zsh/custom/themes
nano ~/.oh-my-zsh/custom/themes/mytheme.zsh-theme
```

**Simple example:**
```zsh
PROMPT='%F{cyan}%n%f@%F{green}%m%f:%F{yellow}%~%f$ '
```

**Use it:**
```zsh
# In .zshrc
ZSH_THEME="mytheme"
```

### Conditional Plugin Loading

**Load plugins based on conditions:**
```zsh
# In .zshrc
plugins=(git macos)

# Add docker plugin only if docker is installed
(( $+commands[docker] )) && plugins+=(docker)

# Add kubectl plugin only if kubectl is installed
(( $+commands[kubectl] )) && plugins+=(kubectl)
```

### Custom Completion

**Add custom completion:**
```bash
mkdir -p ~/.oh-my-zsh/custom/completions
# Add completion files there
```

**Example:**
```bash
# ~/.oh-my-zsh/custom/completions/_mycmd
#compdef mycmd

_mycmd() {
    _arguments \
        '1:command:(start stop restart)' \
        '--help[Show help]'
}
```

### Git Hooks Integration

**Add to functions.zsh:**
```zsh
# Auto-commit dotfiles on change
function dotfiles-autocommit() {
    cd ~/Repositories/dotfiles
    git add -A
    git commit -m "Auto-commit: $(date)"
    git push
}

# Commit before running sync
function sync-vscode-and-commit() {
    cd ~/Repositories/dotfiles
    ./sync-vscode.sh
    git add vscode/
    git commit -m "Update VS Code config: $(date +%Y-%m-%d)"
}
```

---

## Testing Customizations

### Safe Testing

**1. Test in new shell without committing:**
```bash
# Edit files
nano ~/Repositories/dotfiles/zsh/aliases.zsh

# Test in new shell
zsh

# If works, commit
git add .
git commit -m "Add new aliases"
```

**2. Test specific component:**
```bash
# Test alias file
source ~/Repositories/dotfiles/zsh/aliases.zsh

# Test function
source ~/Repositories/dotfiles/zsh/functions.zsh
myfunction
```

**3. Syntax check:**
```bash
# Check zsh syntax
zsh -n ~/Repositories/dotfiles/zsh/.zshrc

# Check for errors without executing
zsh -f -c 'source ~/Repositories/dotfiles/zsh/.zshrc'
```

---

## Customization Workflow

**Recommended workflow:**

1. **Make changes** in dotfiles repo
2. **Test** in new terminal window
3. **Verify** functionality
4. **Commit** with descriptive message
5. **Push** to remote
6. **Document** significant changes

**Example:**
```bash
# 1. Make changes
nano ~/Repositories/dotfiles/zsh/aliases.zsh

# 2. Test
exec zsh
myalias  # Test it works

# 3. Commit
cd ~/Repositories/dotfiles
git add zsh/aliases.zsh
git commit -m "Add alias for quick project navigation"

# 4. Push
git push

# 5. Apply on other machines
# (on other machine)
cd ~/Repositories/dotfiles
git pull
exec zsh
```

---

## Resources

- [Oh-My-Zsh Themes](https://github.com/ohmyzsh/ohmyzsh/wiki/Themes)
- [Oh-My-Zsh Plugins](https://github.com/ohmyzsh/ohmyzsh/wiki/Plugins)
- [VS Code Settings](https://code.visualstudio.com/docs/getstarted/settings)
- [macOS defaults](https://macos-defaults.com/)
- [Awesome Dotfiles](https://github.com/webpro/awesome-dotfiles)
