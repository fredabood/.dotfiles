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
