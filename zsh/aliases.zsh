#!/usr/bin/env zsh

# Curated aliases for zsh
# These complement oh-my-zsh and provide macOS-specific functionality

# ============================================================================
# Time & Date
# ============================================================================

# Get week number
alias week='date +%V'

# ============================================================================
# Network
# ============================================================================

# Get external IP address
alias ip="dig +short myip.opendns.com @resolver1.opendns.com"

# Get local IP address
alias localip="ipconfig getifaddr en0"

# Show all IP addresses
alias ips="ifconfig -a | grep -o 'inet6\? \(addr:\)\?\s\?\(\(\([0-9]\+\.\)\{3\}[0-9]\+\)\|[a-fA-F0-9:]\+\)' | awk '{ sub(/inet6? (addr:)? ?/, \"\"); print }'"

# ============================================================================
# macOS Specific
# ============================================================================

# Recursively delete .DS_Store files
alias cleanup="find . -type f -name '*.DS_Store' -ls -delete"

# Empty the Trash on all mounted volumes and the main HDD
# Also clear Apple's System Logs and download history
alias emptytrash="sudo rm -rfv /Volumes/*/.Trashes; sudo rm -rfv ~/.Trash; sudo rm -rfv /private/var/log/asl/*.asl; sqlite3 ~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV* 'delete from LSQuarantineEvent'"

# Show/hide hidden files in Finder
alias show="defaults write com.apple.finder AppleShowAllFiles -bool true && killall Finder"
alias hide="defaults write com.apple.finder AppleShowAllFiles -bool false && killall Finder"

# Hide/show all desktop icons (useful when presenting)
alias hidedesktop="defaults write com.apple.finder CreateDesktop -bool false && killall Finder"
alias showdesktop="defaults write com.apple.finder CreateDesktop -bool true && killall Finder"

# PlistBuddy alias (because sometimes `defaults` doesn't cut it)
alias plistbuddy="/usr/libexec/PlistBuddy"

# Airport CLI alias for WiFi debugging
alias airport='/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport'

# Mute audio output
alias stfu="osascript -e 'set volume output muted true'"

# Lock the screen (when going AFK)
alias afk="/System/Library/CoreServices/Menu\ Extras/User.menu/Contents/Resources/CGSession -suspend"

# ============================================================================
# Utilities
# ============================================================================

# Print each PATH entry on a separate line
alias path='echo -e ${PATH//:/\\n}'

# Search history with grep
alias h="history | grep -i"

# Sudo last command (because typing sudo !! is annoying)
alias please='sudo $(fc -ln -1)'

# Remove recursively (safer than rm -rf)
alias rmr='rm -r'

# ============================================================================
# Chrome (if you use it for development)
# ============================================================================

# Google Chrome
alias chrome='/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome'
