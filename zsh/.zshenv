#!/usr/bin/env zsh

# Environment variables for zsh
# This file is sourced on all shell invocations

# ============================================================================
# Editor
# ============================================================================

# Make vim the default editor (update to your preference)
export EDITOR='vim'
export VISUAL='vim'

# ============================================================================
# Node.js
# ============================================================================

# Enable persistent REPL history for `node`
export NODE_REPL_HISTORY=~/.node_history

# Allow 32³ entries; the default is 1000
export NODE_REPL_HISTORY_SIZE='32768'

# Use sloppy mode by default, matching web browsers
export NODE_REPL_MODE='sloppy'

# ============================================================================
# Python
# ============================================================================

# Make Python use UTF-8 encoding for output to stdin, stdout, and stderr
export PYTHONIOENCODING='UTF-8'

# ============================================================================
# History (zsh-specific, complements oh-my-zsh settings)
# ============================================================================

# Increase history size (oh-my-zsh sets defaults, these override if needed)
export HISTSIZE=50000
export SAVEHIST=50000

# ============================================================================
# Less / Man pages
# ============================================================================

# Highlight section titles in manual pages
export LESS_TERMCAP_md="${yellow}"

# Don't clear the screen after quitting a manual page
export MANPAGER='less -X'

# ============================================================================
# GPG
# ============================================================================

# Avoid issues with `gpg` as installed via Homebrew
# https://stackoverflow.com/a/42265848/96656
export GPG_TTY=$(tty)

# ============================================================================
# Language & Locale
# ============================================================================

# Prefer US English and use UTF-8
export LANG='en_US.UTF-8'
export LC_ALL='en_US.UTF-8'

# ============================================================================
# Development Directories
# ============================================================================

# Python virtual environments directory (if you use virtualenv/venv)
# Update or remove if you use a different Python environment manager
export VENV_DIR="$HOME/.venv"
