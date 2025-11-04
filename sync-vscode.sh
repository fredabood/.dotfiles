#!/usr/bin/env zsh

# ============================================================================
# VS Code Configuration Sync Script
# ============================================================================
# This script pulls your current VS Code configuration from your system
# into the dotfiles repository so it can be version controlled and synced.
#
# Usage: ./sync-vscode.sh

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the directory where this script is located
DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
VSCODE_DIR="$DOTFILES_DIR/vscode"

# VS Code settings location on macOS
VSCODE_USER_DIR="$HOME/Library/Application Support/Code/User"

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

# ============================================================================
# Pre-flight Checks
# ============================================================================

print_header "VS Code Configuration Sync"

# Check if VS Code is installed
if ! command -v code &> /dev/null; then
    print_error "VS Code CLI 'code' command not found."
    echo "Install it from VS Code: ${BLUE}View → Command Palette → Shell Command: Install 'code' command in PATH${NC}"
    exit 1
fi

# Check if VS Code settings directory exists
if [[ ! -d "$VSCODE_USER_DIR" ]]; then
    print_error "VS Code settings directory not found at: $VSCODE_USER_DIR"
    echo "Make sure VS Code has been run at least once."
    exit 1
fi

print_success "VS Code installation found"

# ============================================================================
# Create VS Code Directory Structure
# ============================================================================

print_header "Preparing Directory Structure"

mkdir -p "$VSCODE_DIR/snippets"
print_success "Created vscode/ directory structure"

# ============================================================================
# Sync Settings
# ============================================================================

print_header "Syncing VS Code Settings"

# Copy settings.json
if [[ -f "$VSCODE_USER_DIR/settings.json" ]]; then
    cp "$VSCODE_USER_DIR/settings.json" "$VSCODE_DIR/settings.json"
    print_success "Synced settings.json"
else
    print_warning "settings.json not found (this is okay if you haven't customized VS Code yet)"
    # Create a minimal settings.json
    echo '{}' > "$VSCODE_DIR/settings.json"
    print_success "Created empty settings.json"
fi

# Copy keybindings.json
if [[ -f "$VSCODE_USER_DIR/keybindings.json" ]]; then
    cp "$VSCODE_USER_DIR/keybindings.json" "$VSCODE_DIR/keybindings.json"
    print_success "Synced keybindings.json"
else
    print_warning "keybindings.json not found"
    # Create an empty keybindings.json
    echo '[]' > "$VSCODE_DIR/keybindings.json"
    print_success "Created empty keybindings.json"
fi

# ============================================================================
# Sync Snippets
# ============================================================================

print_header "Syncing Code Snippets"

if [[ -d "$VSCODE_USER_DIR/snippets" ]]; then
    snippet_count=$(ls -1 "$VSCODE_USER_DIR/snippets" 2>/dev/null | wc -l | tr -d ' ')

    if [[ $snippet_count -gt 0 ]]; then
        cp "$VSCODE_USER_DIR/snippets"/*.json "$VSCODE_DIR/snippets/" 2>/dev/null || true
        print_success "Synced $snippet_count snippet file(s)"
    else
        print_warning "No custom snippets found"
    fi
else
    print_warning "Snippets directory not found"
fi

# Create README in snippets directory
cat > "$VSCODE_DIR/snippets/README.md" << 'EOF'
# VS Code Snippets

This directory contains custom code snippets for VS Code.

Snippet files are named by language:
- `javascript.json` - JavaScript snippets
- `typescript.json` - TypeScript snippets
- `python.json` - Python snippets
- etc.

Learn more about snippets: https://code.visualstudio.com/docs/editor/userdefinedsnippets
EOF

# ============================================================================
# Export Extensions List
# ============================================================================

print_header "Exporting Extensions List"

# Get list of installed extensions
code --list-extensions > "$VSCODE_DIR/extensions.txt"
extension_count=$(wc -l < "$VSCODE_DIR/extensions.txt" | tr -d ' ')
print_success "Exported $extension_count extension(s) to extensions.txt"

# ============================================================================
# Create Installation Script for Extensions
# ============================================================================

print_header "Generating Extension Install Script"

cat > "$VSCODE_DIR/install-extensions.sh" << 'EOF'
#!/usr/bin/env zsh

# Install VS Code extensions from extensions.txt
# This script is auto-generated by sync-vscode.sh

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
EXTENSIONS_FILE="$SCRIPT_DIR/extensions.txt"

if [[ ! -f "$EXTENSIONS_FILE" ]]; then
    echo "Error: extensions.txt not found"
    exit 1
fi

if ! command -v code &> /dev/null; then
    echo "Error: VS Code CLI 'code' command not found"
    exit 1
fi

echo "Installing VS Code extensions..."
while IFS= read -r extension; do
    if [[ -n "$extension" ]]; then
        echo "Installing: $extension"
        code --install-extension "$extension" --force
    fi
done < "$EXTENSIONS_FILE"

echo "✓ Extension installation complete"
EOF

chmod +x "$VSCODE_DIR/install-extensions.sh"
print_success "Created install-extensions.sh"

# ============================================================================
# Create README for VS Code Directory
# ============================================================================

print_header "Creating Documentation"

cat > "$VSCODE_DIR/README.md" << 'EOF'
# VS Code Configuration

This directory contains VS Code settings, keybindings, snippets, and extensions list.

## Files

- `settings.json` - VS Code settings
- `keybindings.json` - Custom keyboard shortcuts
- `extensions.txt` - List of installed extensions
- `install-extensions.sh` - Script to install all extensions
- `snippets/` - Custom code snippets

## Usage

### Apply Settings (via install.sh)

The main `install.sh` script will automatically symlink these configs:

```bash
cd ~/.dotfiles
./install.sh
```

### Manual Setup

If you prefer to set up VS Code manually:

```bash
# Symlink settings
ln -sf ~/.dotfiles/vscode/settings.json ~/Library/Application\ Support/Code/User/settings.json
ln -sf ~/.dotfiles/vscode/keybindings.json ~/Library/Application\ Support/Code/User/keybindings.json

# Install extensions
./install-extensions.sh

# Symlink snippets (optional)
rm -rf ~/Library/Application\ Support/Code/User/snippets
ln -sf ~/.dotfiles/vscode/snippets ~/Library/Application\ Support/Code/User/snippets
```

### Update Dotfiles with Current VS Code Config

After making changes to VS Code settings, sync them back to the repo:

```bash
cd ~/.dotfiles
./sync-vscode.sh
git add vscode/
git commit -m "Update VS Code configuration"
```

## Extensions

The `extensions.txt` file contains a list of all installed extensions. To install them:

```bash
./install-extensions.sh
```

Or manually:

```bash
cat extensions.txt | xargs -L 1 code --install-extension
```

## Snippets

Custom snippets are organized by language in the `snippets/` directory:
- `javascript.json` - JavaScript snippets
- `typescript.json` - TypeScript snippets
- `python.json` - Python snippets
- etc.

## Notes

- Settings are synced to your home directory via symlinks
- Changes made in VS Code will automatically update the dotfiles repo
- Run `./sync-vscode.sh` to pull changes from VS Code into the repo
- Don't forget to commit and push changes to git!
EOF

print_success "Created vscode/README.md"

# ============================================================================
# Summary
# ============================================================================

print_header "Sync Complete!"

echo "\n${GREEN}Successfully synced VS Code configuration!${NC}\n"
echo "Files synced to: ${BLUE}$VSCODE_DIR${NC}"
echo ""
echo "Next steps:"
echo "  1. Review the synced files: ${BLUE}ls -la vscode/${NC}"
echo "  2. Check settings: ${BLUE}cat vscode/settings.json${NC}"
echo "  3. Review extensions: ${BLUE}cat vscode/extensions.txt${NC}"
echo "  4. Commit to git: ${BLUE}git add vscode/ && git commit -m 'Add VS Code configuration'${NC}"
echo ""
echo "To apply these settings on another machine:"
echo "  ${BLUE}./install.sh${NC} (will include VS Code setup)"
echo ""
echo "To update dotfiles with new VS Code changes:"
echo "  ${BLUE}./sync-vscode.sh${NC}"
echo ""
