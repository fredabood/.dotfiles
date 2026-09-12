#!/usr/bin/env zsh

# ============================================================================
# Dotfiles Installation Script
# ============================================================================
# This script installs and configures a modern zsh-based development environment
# optimized for macOS with oh-my-zsh integration.

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the directory where this script is located
DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    echo "\n${BLUE}==>${NC} ${1}"
}

print_success() {
    echo "${GREEN}✓${NC} ${1}"
}

print_warning() {
    echo "${YELLOW}⚠${NC} ${1}"
}

print_error() {
    echo "${RED}✗${NC} ${1}"
}

ask_yes_no() {
    while true; do
        read "response?${1} (y/n): "
        case $response in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer y or n.";;
        esac
    done
}

# ============================================================================
# Pre-flight Checks
# ============================================================================

print_header "Pre-flight Checks"

# Check if we're on macOS
if [[ ! "$OSTYPE" == "darwin"* ]]; then
    print_error "This script is designed for macOS only."
    exit 1
fi

print_success "Running on macOS"

# ============================================================================
# Install Homebrew
# ============================================================================

print_header "Checking Homebrew"

if ! command -v brew &> /dev/null; then
    print_warning "Homebrew not found. Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add Homebrew to PATH for Apple Silicon Macs
    if [[ -d "/opt/homebrew/bin" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi

    print_success "Homebrew installed"
else
    print_success "Homebrew already installed"
fi

# ============================================================================
# Install Oh-My-Zsh
# ============================================================================

print_header "Checking Oh-My-Zsh"

if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    print_warning "Oh-My-Zsh not found. Installing..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    print_success "Oh-My-Zsh installed"
else
    print_success "Oh-My-Zsh already installed"
fi

# ============================================================================
# Install Homebrew Packages
# ============================================================================

print_header "Installing Homebrew Packages"

if ask_yes_no "Install packages from Brewfile?"; then
    cd "$DOTFILES_DIR"
    brew bundle --file=brew/Brewfile
    print_success "Homebrew packages installed"
else
    print_warning "Skipping Homebrew package installation"
fi

# ============================================================================
# Install Oh-My-Zsh Plugins
# ============================================================================

print_header "Installing Oh-My-Zsh Plugins"

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

# Install zsh-autosuggestions
if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]; then
    if ask_yes_no "Install zsh-autosuggestions plugin?"; then
        git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
        print_success "zsh-autosuggestions installed"
    fi
else
    print_success "zsh-autosuggestions already installed"
fi

# Install zsh-syntax-highlighting
if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]]; then
    if ask_yes_no "Install zsh-syntax-highlighting plugin?"; then
        git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
        print_success "zsh-syntax-highlighting installed"
    fi
else
    print_success "zsh-syntax-highlighting already installed"
fi

# ============================================================================
# Symlink Configuration Files
# ============================================================================

print_header "Setting Up Configuration Files"

# Backup existing files
backup_if_exists() {
    if [[ -f "$1" ]] && [[ ! -L "$1" ]]; then
        local backup_path="${1}.backup.$(date +%Y%m%d_%H%M%S)"
        mv "$1" "$backup_path"
        print_warning "Backed up existing $1 to $backup_path"
    fi
}

# Symlink zsh configuration
backup_if_exists "$HOME/.zshrc"
ln -sf "$DOTFILES_DIR/zsh/.zshrc" "$HOME/.zshrc"
print_success "Linked .zshrc"

backup_if_exists "$HOME/.zshenv"
ln -sf "$DOTFILES_DIR/zsh/.zshenv" "$HOME/.zshenv"
print_success "Linked .zshenv"

# Symlink vim configuration
if ask_yes_no "Link vim configuration?"; then
    backup_if_exists "$HOME/.vimrc"
    ln -sf "$DOTFILES_DIR/editors/.vimrc" "$HOME/.vimrc"

    # Create vim directories
    mkdir -p "$HOME/.vim/"{backups,swaps,undo}
    print_success "Linked .vimrc and created vim directories"
fi

# Symlink editorconfig
if ask_yes_no "Link .editorconfig?"; then
    backup_if_exists "$HOME/.editorconfig"
    ln -sf "$DOTFILES_DIR/editors/.editorconfig" "$HOME/.editorconfig"
    print_success "Linked .editorconfig"
fi

# Symlink git configuration
if [[ -f "$DOTFILES_DIR/git/.gitconfig" ]]; then
    if ask_yes_no "Link git configuration?"; then
        backup_if_exists "$HOME/.gitconfig"
        ln -sf "$DOTFILES_DIR/git/.gitconfig" "$HOME/.gitconfig"
        print_success "Linked .gitconfig"
    fi
fi

if [[ -f "$DOTFILES_DIR/git/.gitignore_global" ]]; then
    if ask_yes_no "Link global gitignore?"; then
        backup_if_exists "$HOME/.gitignore_global"
        ln -sf "$DOTFILES_DIR/git/.gitignore_global" "$HOME/.gitignore_global"
        print_success "Linked .gitignore_global"
    fi
fi

# ============================================================================
# VS Code Configuration
# ============================================================================

print_header "VS Code Configuration"

VSCODE_USER_DIR="$HOME/Library/Application Support/Code/User"

if [[ -d "$DOTFILES_DIR/vscode" ]]; then
    if ask_yes_no "Link VS Code settings?"; then
        # Create VS Code User directory if it doesn't exist
        mkdir -p "$VSCODE_USER_DIR"

        # Symlink settings.json
        if [[ -f "$DOTFILES_DIR/vscode/settings.json" ]]; then
            backup_if_exists "$VSCODE_USER_DIR/settings.json"
            ln -sf "$DOTFILES_DIR/vscode/settings.json" "$VSCODE_USER_DIR/settings.json"
            print_success "Linked VS Code settings.json"
        fi

        # Symlink keybindings.json
        if [[ -f "$DOTFILES_DIR/vscode/keybindings.json" ]]; then
            backup_if_exists "$VSCODE_USER_DIR/keybindings.json"
            ln -sf "$DOTFILES_DIR/vscode/keybindings.json" "$VSCODE_USER_DIR/keybindings.json"
            print_success "Linked VS Code keybindings.json"
        fi

        # Symlink snippets directory
        if [[ -d "$DOTFILES_DIR/vscode/snippets" ]]; then
            if ask_yes_no "Link VS Code snippets?"; then
                backup_if_exists "$VSCODE_USER_DIR/snippets"
                # Remove existing snippets directory if it's not a symlink
                if [[ -d "$VSCODE_USER_DIR/snippets" ]] && [[ ! -L "$VSCODE_USER_DIR/snippets" ]]; then
                    mv "$VSCODE_USER_DIR/snippets" "$VSCODE_USER_DIR/snippets.backup.$(date +%Y%m%d_%H%M%S)"
                    print_warning "Backed up existing snippets directory"
                fi
                ln -sf "$DOTFILES_DIR/vscode/snippets" "$VSCODE_USER_DIR/snippets"
                print_success "Linked VS Code snippets"
            fi
        fi

        # Install extensions
        if [[ -f "$DOTFILES_DIR/vscode/extensions.txt" ]]; then
            if command -v code &> /dev/null; then
                if ask_yes_no "Install VS Code extensions from extensions.txt?"; then
                    print_warning "Installing extensions (this may take a few minutes)..."
                    cd "$DOTFILES_DIR/vscode"
                    ./install-extensions.sh
                    print_success "VS Code extensions installed"
                fi
            else
                print_warning "VS Code CLI 'code' not found. Skipping extension installation."
                echo "Install the CLI from VS Code: View → Command Palette → Shell Command: Install 'code' command in PATH"
            fi
        fi
    fi
else
    print_warning "VS Code configuration not found. Run ./sync-vscode.sh to create it."
fi

# ============================================================================
# iTerm2 Configuration
# ============================================================================

print_header "iTerm2 Configuration"

if [[ -d "$DOTFILES_DIR/iterm" ]]; then
    if ask_yes_no "Point iTerm2 at ~/Repositories/dotfiles/iterm for preferences?"; then
        print_warning "Quit iTerm2 before continuing if it's running."
        defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$DOTFILES_DIR/iterm"
        defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true
        print_success "iTerm2 will load prefs from $DOTFILES_DIR/iterm"
        echo "  On first launch, choose 'Save' when prompted so changes persist to the repo."
    fi
else
    print_warning "iTerm2 configuration not found at $DOTFILES_DIR/iterm"
fi

# ============================================================================
# Claude Code Configuration
# ============================================================================

print_header "Claude Code Configuration"

# This repo is public: block credentials and private information at commit time.
git -C "$DOTFILES_DIR" config core.hooksPath .githooks
print_success "Enabled the public-content pre-commit check (.githooks)"

if [[ -d "$DOTFILES_DIR/claude" ]]; then
    if [[ ! -d "${MEMORY_VAULT_PATH:-$HOME/Repositories/memory}" ]]; then
        print_warning "Memory vault not found — clone fredabood/memory.md to ~/Repositories/memory first for the private settings overlay and profile"
    fi
    if ask_yes_no "Link Claude Code config into ~/.claude?"; then
        # claude/install.sh refuses rather than clobbering unabsorbed settings drift;
        # under `set -e` that must not abort the rest of this installer.
        if "$DOTFILES_DIR/claude/install.sh"; then
            print_success "Claude Code config linked and settings.json generated"
        else
            print_warning "claude/install.sh reported a problem — see above; re-run it once resolved"
        fi
    fi
else
    print_warning "Claude Code configuration not found at $DOTFILES_DIR/claude"
fi

# ============================================================================
# macOS Defaults
# ============================================================================

print_header "macOS System Preferences"

if ask_yes_no "Apply macOS system preferences? (This will require sudo and restart some apps)"; then
    print_warning "This will configure various macOS settings. Review macos/defaults.sh before proceeding."
    if ask_yes_no "Are you sure you want to continue?"; then
        cd "$DOTFILES_DIR"
        bash macos/defaults.sh
        print_success "macOS preferences applied"
    fi
else
    print_warning "Skipping macOS preferences"
fi

# ============================================================================
# Completion
# ============================================================================

print_header "Installation Complete!"

echo "\n${GREEN}Your dotfiles have been installed successfully!${NC}\n"
echo "Next steps:"
echo "  1. Restart your terminal or run: ${BLUE}exec zsh${NC}"
echo "  2. Review and customize ${BLUE}~/.zshrc${NC} if needed"
echo "  3. Edit ${BLUE}~/.zshrc.local${NC} for machine-specific settings"
echo "  4. Consider enabling these oh-my-zsh plugins in ${BLUE}zsh/.zshrc${NC}:"
echo "     - zsh-autosuggestions"
echo "     - zsh-syntax-highlighting"
echo "     - brew, docker, node, python, etc."
echo ""
echo "VS Code:"
echo "  - Settings are now symlinked to ${BLUE}~/Repositories/dotfiles/vscode/${NC}"
echo "  - Changes in VS Code will automatically update your dotfiles"
echo "  - To sync VS Code config to repo: ${BLUE}./sync-vscode.sh${NC}"
echo ""
echo "Claude Code:"
echo "  - Agents, commands, rules, hooks and skills are symlinked from ${BLUE}~/Repositories/dotfiles/claude/${NC}"
echo "  - settings.json is generated: ${BLUE}~/Repositories/dotfiles/claude/scripts/claude-settings status${NC}"
echo ""
echo "\n${YELLOW}Note:${NC} Your original config files were backed up with timestamps."
echo ""
