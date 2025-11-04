#!/usr/bin/env zsh

# PATH management for zsh
# Add custom directories to PATH

# ============================================================================
# User Binaries
# ============================================================================

# Add user's private bin to PATH if it exists
[[ -d "$HOME/bin" ]] && export PATH="$HOME/bin:$PATH"

# Add user's local bin to PATH if it exists
[[ -d "$HOME/.local/bin" ]] && export PATH="$HOME/.local/bin:$PATH"

# ============================================================================
# Homebrew
# ============================================================================

# Add Homebrew paths (for Apple Silicon and Intel Macs)
if [[ -d "/opt/homebrew/bin" ]]; then
	# Apple Silicon Mac
	export PATH="/opt/homebrew/bin:$PATH"
elif [[ -d "/usr/local/bin" ]]; then
	# Intel Mac
	export PATH="/usr/local/bin:$PATH"
fi

# ============================================================================
# Language-Specific Paths
# ============================================================================

# Java (OpenJDK via Homebrew)
[[ -d "/usr/local/opt/openjdk/bin" ]] && export PATH="/usr/local/opt/openjdk/bin:$PATH"
[[ -d "/opt/homebrew/opt/openjdk/bin" ]] && export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"

# Python (if using pyenv, uncomment and adjust)
# [[ -d "$HOME/.pyenv/bin" ]] && export PATH="$HOME/.pyenv/bin:$PATH"
# eval "$(pyenv init -)"

# Node (if using nvm, it should be initialized separately)
# export NVM_DIR="$HOME/.nvm"
# [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Ruby (if using rbenv, uncomment)
# [[ -d "$HOME/.rbenv/bin" ]] && export PATH="$HOME/.rbenv/bin:$PATH"
# eval "$(rbenv init -)"

# Go
[[ -d "$HOME/go/bin" ]] && export PATH="$HOME/go/bin:$PATH"

# Rust
[[ -d "$HOME/.cargo/bin" ]] && export PATH="$HOME/.cargo/bin:$PATH"

# ============================================================================
# Other Tools
# ============================================================================

# Add any other custom paths here
