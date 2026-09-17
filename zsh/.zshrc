#!/usr/bin/env zsh

# ============================================================================
# Oh-My-Zsh Configuration
# ============================================================================

# Path to oh-my-zsh installation
export ZSH="$HOME/.oh-my-zsh"

# Set theme (see https://github.com/ohmyzsh/ohmyzsh/wiki/Themes)
# Popular themes: robbyrussell (default), agnoster, powerlevel10k/powerlevel10k
ZSH_THEME="robbyrussell"

# Uncomment to use case-sensitive completion
# CASE_SENSITIVE="true"

# Uncomment to use hyphen-insensitive completion (case-sensitive must be off)
# HYPHEN_INSENSITIVE="true"

# Auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
zstyle ':omz:update' mode reminder    # just remind me to update when it's time

# Update frequency (in days)
zstyle ':omz:update' frequency 13

# Uncomment to disable colors in ls
# DISABLE_LS_COLORS="true"

# Uncomment to disable auto-setting terminal title
# DISABLE_AUTO_TITLE="true"

# Uncomment to enable command auto-correction
# ENABLE_CORRECTION="true"

# Uncomment to display red dots whilst waiting for completion
# COMPLETION_WAITING_DOTS="true"

# Uncomment to disable marking untracked files under VCS as dirty
# This makes repository status checks much faster on large repositories
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# History timestamp format (see 'man strftime' for format options)
# HIST_STAMPS="mm/dd/yyyy"

# ============================================================================
# Oh-My-Zsh Plugins
# ============================================================================

# Standard plugins are in $ZSH/plugins/
# Custom plugins can be added to $ZSH_CUSTOM/plugins/
#
# Recommended plugins to consider:
#   git - Git aliases and functions (highly recommended)
#   brew - Homebrew aliases and completion
#   macos - macOS specific aliases and functions
#   docker - Docker aliases and completion
#   node - Node.js aliases
#   npm - npm completion
#   python - Python aliases
#   z - Jump to frequent directories
#   zsh-autosuggestions - Fish-like fast/unobtrusive autosuggestions (install separately)
#   zsh-syntax-highlighting - Syntax highlighting for zsh (install separately)
#
# To install zsh-autosuggestions:
#   git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
#
# To install zsh-syntax-highlighting:
#   git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

plugins=(
	git
	macos
	# brew
	# docker
	# z
	# zsh-autosuggestions
	# zsh-syntax-highlighting
)

# Load Oh-My-Zsh
source $ZSH/oh-my-zsh.sh

# ============================================================================
# User Configuration
# ============================================================================

# Locate the dotfiles repo from this file's own path. ~/.zshrc is a symlink into
# the repo, and ${0:A} resolves it, so the repo can be cloned anywhere without
# editing this file. Falls back to the conventional location if $0 is not a path.
DOTFILES_DIR="${${0:A}:h:h}"
[[ -d "$DOTFILES_DIR/zsh" ]] || DOTFILES_DIR="$HOME/Repositories/dotfiles"
export DOTFILES_DIR

# Source environment variables
[[ -f "$DOTFILES_DIR/zsh/.zshenv" ]] && source "$DOTFILES_DIR/zsh/.zshenv"

# Source PATH configuration
[[ -f "$DOTFILES_DIR/zsh/path.zsh" ]] && source "$DOTFILES_DIR/zsh/path.zsh"

# Source custom aliases
[[ -f "$DOTFILES_DIR/zsh/aliases.zsh" ]] && source "$DOTFILES_DIR/zsh/aliases.zsh"

# Source custom functions
[[ -f "$DOTFILES_DIR/zsh/functions.zsh" ]] && source "$DOTFILES_DIR/zsh/functions.zsh"

# Source local customizations (not tracked in git)
# Create ~/.zshrc.local for machine-specific settings
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"

# ============================================================================
# Additional Configuration
# ============================================================================

# Preferred editor for local and remote sessions
if [[ -n $SSH_CONNECTION ]]; then
	export EDITOR='vim'
else
	export EDITOR='vim'  # or 'code --wait' for VS Code
fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# ============================================================================
# FZF Configuration (if installed)
# ============================================================================

# Setup fzf key bindings and fuzzy completion
if [[ -f ~/.fzf.zsh ]]; then
	source ~/.fzf.zsh
fi

# ============================================================================
# Additional Tool Initialization
# ============================================================================

# Add any additional tool initialization here
# Examples:
# - pyenv init
# - rbenv init
# - nvm loading
# - direnv hook

export PATH="$HOME/bin:$PATH"

# Atlassian MCP + Anthropic credentials live in ~/.zshrc.local (gitignored,
# sourced above). Never put tokens in this file — it is a public repo.
export PATH="$HOME/.local/bin:$PATH"


# kimi-code
export PATH="/Users/fredabood/.kimi-code/bin:$PATH"

# Qwen Code PATH block begin
export PATH='/Users/fredabood/.local/bin':$PATH
# Qwen Code PATH block end


# Added by Antigravity CLI installer
export PATH="/Users/fredabood/.local/bin:$PATH"
