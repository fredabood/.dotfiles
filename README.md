# Dotfiles

Modern, zsh-focused dotfiles for macOS that integrate seamlessly with [oh-my-zsh](https://ohmyz.sh/).

Originally forked from [Mathias' Dotfiles](https://github.com/mathiasbynens/dotfiles), this repository has been modernized for zsh and current macOS development workflows.

## Features

- 🐚 **Zsh Configuration** - Optimized for oh-my-zsh with custom aliases and functions
- 🍺 **Homebrew Bundle** - Declarative package management with Brewfile
- 🎨 **macOS Customization** - Comprehensive system preferences automation
- ⚡ **Development Tools** - Curated utilities and editor configurations
- 🤖 **Claude Code** - Agents, commands, rules, hooks and skills linked into `~/.claude`; `settings.json` generated from a public base + private overlay
- 📦 **Modular Organization** - Clean separation of concerns

## Repository Structure

```
.dotfiles/
├── zsh/                    # Zsh configuration
│   ├── .zshrc             # Main zsh config (sources other files)
│   ├── .zshenv            # Environment variables
│   ├── aliases.zsh        # Custom aliases
│   ├── functions.zsh      # Custom functions
│   └── path.zsh           # PATH management
├── macos/                 # macOS system preferences
│   └── defaults.sh        # System configuration script
├── editors/               # Editor configurations
│   ├── .vimrc            # Vim configuration
│   └── .editorconfig     # Universal editor config
├── git/                   # Git configuration
│   ├── .gitconfig        # Git settings
│   └── .gitignore_global # Global gitignore patterns
├── vscode/                # VS Code configuration
│   ├── settings.json     # VS Code settings
│   ├── keybindings.json  # Custom keybindings
│   ├── extensions.txt    # Installed extensions list
│   └── snippets/         # Code snippets
├── claude/                # Claude Code configuration (see claude/README.md)
│   ├── agents/ commands/ rules/ hooks/ skills/   # each folder linked into ~/.claude — new items live immediately
│   ├── settings.base.json # Public half of ~/.claude/settings.json
│   ├── install.sh        # Linker + settings generation
│   └── scripts/          # claude-settings, check-public.sh, merge/subtract jq
├── .githooks/             # pre-commit: gitleaks + private denylist (public repo)
├── brew/                  # Homebrew packages
│   └── Brewfile          # Package definitions
├── deprecated/            # Archived configurations
│   ├── bash/             # Old bash configs
│   ├── conda/            # Old conda configs
│   └── docker/           # Old Docker setup
├── docs/                   # Comprehensive documentation
├── install.sh            # Installation script
└── sync-vscode.sh        # Sync VS Code config to repo
```

## Documentation

📚 **Comprehensive guides available in the `docs/` directory:**

### Getting Started
- **[Setup Guide](docs/SETUP.md)** - Detailed installation instructions, step-by-step setup, and verification
- **[Quick Start](#installation)** - Fast installation for experienced users (below)

### Reference
- **[Components Documentation](docs/COMPONENTS.md)** - Detailed documentation for each component (zsh, VS Code, brew, etc.)
- **[Architecture](docs/ARCHITECTURE.md)** - Design decisions, philosophy, and technical architecture
- **[Changelog](CHANGELOG.md)** - Version history and upgrade notes

### Customization & Help
- **[Customization Guide](docs/CUSTOMIZATION.md)** - How to personalize aliases, functions, themes, and settings
- **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Common issues and solutions
- **[FAQ](docs/FAQ.md)** - Frequently asked questions
- **[Migration Guide](MIGRATION.md)** - Details on the bash → zsh migration

### Quick Links
| I want to... | Read this |
|--------------|-----------|
| Install for the first time | [Setup Guide](docs/SETUP.md) |
| Fix an issue | [Troubleshooting](docs/TROUBLESHOOTING.md) |
| Customize my setup | [Customization Guide](docs/CUSTOMIZATION.md) |
| Understand the structure | [Architecture](docs/ARCHITECTURE.md) |
| Learn about components | [Components](docs/COMPONENTS.md) |
| See what changed | [Changelog](CHANGELOG.md) |

---

## Installation

**Warning:** Review the code before installing! These are personal configurations that may not suit everyone.

### Quick Start

```bash
# Clone the repository
git clone https://github.com/fredabood/.dotfiles.git ~/.dotfiles

# Navigate to the directory
cd ~/.dotfiles

# Run the installation script
./install.sh
```

The installation script will:
1. ✅ Check for and install Homebrew (if needed)
2. ✅ Install oh-my-zsh (if needed)
3. ✅ Install packages from Brewfile
4. ✅ Install recommended oh-my-zsh plugins
5. ✅ Symlink configuration files to your home directory
6. ✅ Optionally apply macOS system preferences

### Manual Installation

If you prefer manual installation:

```bash
# Install Homebrew packages
cd ~/.dotfiles
brew bundle --file=brew/Brewfile

# Symlink zsh config
ln -sf ~/.dotfiles/zsh/.zshrc ~/.zshrc
ln -sf ~/.dotfiles/zsh/.zshenv ~/.zshenv

# Symlink editor configs
ln -sf ~/.dotfiles/editors/.vimrc ~/.vimrc
ln -sf ~/.dotfiles/editors/.editorconfig ~/.editorconfig

# Optionally apply macOS preferences
./macos/defaults.sh
```

## Configuration

### Zsh

The main zsh configuration is in `zsh/.zshrc`. It sources:
- `zsh/.zshenv` - Environment variables
- `zsh/path.zsh` - PATH configuration
- `zsh/aliases.zsh` - Custom aliases
- `zsh/functions.zsh` - Custom functions

#### Oh-My-Zsh Plugins

Edit `zsh/.zshrc` to enable additional plugins. Recommended plugins:

```zsh
plugins=(
    git                      # Git aliases (included)
    macos                    # macOS aliases (included)
    brew                     # Homebrew aliases
    docker                   # Docker aliases
    z                        # Directory jumping
    zsh-autosuggestions      # Install separately
    zsh-syntax-highlighting  # Install separately
)
```

To install optional plugins:

```bash
# zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

# zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
```

### Local Customization

Create `~/.zshrc.local` for machine-specific settings that shouldn't be tracked in git:

```bash
# Example ~/.zshrc.local
export CUSTOM_VAR="value"
alias custom-alias="some command"
```

### Homebrew Packages

The `brew/Brewfile` defines all Homebrew packages. To add packages:

```ruby
# In brew/Brewfile
brew "package-name"
cask "application-name"
```

Then run:

```bash
brew bundle --file=~/.dotfiles/brew/Brewfile
```

### macOS Preferences

The `macos/defaults.sh` script configures macOS system preferences. Review and customize before running:

```bash
# Preview what will change
less ~/.dotfiles/macos/defaults.sh

# Apply settings
./macos/defaults.sh
```

**Note:** Some settings require logging out or restarting to take effect.

### VS Code Configuration

VS Code settings, keybindings, snippets, and extensions are fully managed by this dotfiles repo.

#### First Time Setup

1. **Sync your current VS Code config to the repo:**
   ```bash
   cd ~/.dotfiles
   ./sync-vscode.sh
   ```
   This will copy your current VS Code settings, keybindings, snippets, and export your extensions list.

2. **Commit the configuration:**
   ```bash
   git add vscode/
   git commit -m "Add VS Code configuration"
   ```

#### Installing on a New Machine

When you run `./install.sh`, it will:
- Symlink `settings.json` and `keybindings.json` to VS Code
- Symlink the `snippets/` directory
- Optionally install all extensions from `extensions.txt`

#### Updating VS Code Configuration

After making changes to VS Code settings:

```bash
# Settings and keybindings update automatically (they're symlinked)
# But if you install new extensions, sync them:
./sync-vscode.sh

# Then commit
git add vscode/
git commit -m "Update VS Code extensions"
```

#### Manual Extension Management

```bash
# Install all extensions
cd vscode/
./install-extensions.sh

# Or manually
cat extensions.txt | xargs -L 1 code --install-extension
```

#### VS Code CLI Setup

If the `code` command isn't available:
1. Open VS Code
2. Press `Cmd+Shift+P`
3. Type "Shell Command: Install 'code' command in PATH"
4. Select it

**How it works:** Settings and keybindings are symlinked to `~/.dotfiles/vscode/`, so changes in VS Code automatically update your dotfiles. Run `./sync-vscode.sh` to capture extension changes.

## Useful Aliases

### Navigation
- `..`, `...`, `....`, `.....` - Navigate up directories (via oh-my-zsh)
- `1-9` - Jump to recent directories (via oh-my-zsh)

### macOS Specific
- `cleanup` - Recursively delete .DS_Store files
- `emptytrash` - Empty the Trash and system logs
- `show` / `hide` - Toggle hidden files in Finder
- `hidedesktop` / `showdesktop` - Toggle desktop icons
- `afk` - Lock screen

### Network
- `ip` - Get external IP address
- `localip` - Get local IP address

### Utilities
- `week` - Get current week number
- `path` - Print PATH entries on separate lines
- `h [term]` - Search command history
- `please` - Re-run last command with sudo

## Custom Functions

### Directory Management
- `mkd [dir]` - Create directory and cd into it
- `cdf` - Change to the top-most Finder window location

### File Operations
- `targz [file]` - Create optimally compressed tar.gz archive
- `fs [path]` - Show file/directory size
- `dataurl [file]` - Generate data URL from file

### Development
- `tre [path]` - Enhanced tree view with colors
- `search [term]` - Recursive grep search
- `edit [path]` - Open file/directory in editor

See `zsh/functions.zsh` for the complete list.

## Updating

To update your dotfiles:

```bash
cd ~/.dotfiles
git pull origin main

# Reinstall Homebrew packages if Brewfile changed
brew bundle --file=brew/Brewfile

# Reload zsh configuration
exec zsh
```

## Customization

### Change Editor

Edit `zsh/.zshenv`:

```bash
export EDITOR='code --wait'  # VS Code
# or
export EDITOR='nvim'  # Neovim
```

### Change Oh-My-Zsh Theme

Edit `zsh/.zshrc`:

```zsh
ZSH_THEME="agnoster"  # or any other theme
```

Popular themes: `robbyrussell` (default), `agnoster`, `powerlevel10k/powerlevel10k`

### Add Your Own Aliases/Functions

Add to `zsh/aliases.zsh` or `zsh/functions.zsh`, or create `~/.zshrc.local` for local additions.

## Troubleshooting

### Permission Issues

```bash
chmod +x ~/.dotfiles/install.sh
chmod +x ~/.dotfiles/macos/defaults.sh
```

### Oh-My-Zsh Not Loading

Check that oh-my-zsh is installed:

```bash
ls -la ~/.oh-my-zsh
```

If not, install manually:

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

### Broken Symlinks

Remove and recreate:

```bash
rm ~/.zshrc
ln -sf ~/.dotfiles/zsh/.zshrc ~/.zshrc
```

## Deprecated Files

The `deprecated/` directory contains archived configurations:
- `deprecated/bash/` - Old bash configurations (pre-zsh migration)
- `deprecated/conda/` - Conda/Python environment configs
- `deprecated/docker/` - Old Docker containerized environment

These are kept for reference but are not actively maintained.

---

## Learn More

### 📖 Full Documentation

This README provides a quick overview. For comprehensive information, see the full documentation:

**Essential Reading:**
- 📘 **[Setup Guide](docs/SETUP.md)** - Complete installation walkthrough with verification steps
- 🔧 **[Customization Guide](docs/CUSTOMIZATION.md)** - Make it yours: themes, aliases, functions, and more
- ❓ **[FAQ](docs/FAQ.md)** - Answers to common questions
- 🚨 **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Solutions to common problems

**Advanced Topics:**
- 🏗️ **[Architecture](docs/ARCHITECTURE.md)** - Design philosophy and technical decisions
- 🧩 **[Components](docs/COMPONENTS.md)** - Deep dive into each component
- 📝 **[Changelog](CHANGELOG.md)** - Version history and breaking changes
- 🔄 **[Migration Guide](MIGRATION.md)** - Bash to zsh migration details

### 💡 Quick Tips

**After Installation:**
1. Read the [Customization Guide](docs/CUSTOMIZATION.md) to personalize your setup
2. Check [Components Documentation](docs/COMPONENTS.md) to understand what each part does
3. Bookmark [Troubleshooting](docs/TROUBLESHOOTING.md) for quick problem solving

**Regular Maintenance:**
```bash
# Update packages
cd ~/.dotfiles
brew bundle --file=brew/Brewfile

# Sync VS Code extensions (after installing new ones)
./sync-vscode.sh

# Commit changes
git add .
git commit -m "Update configurations"
git push
```

---

## Contributing

This is a personal dotfiles repository, but feel free to fork and adapt for your own use. If you find bugs or have suggestions, please open an issue.

## Credits

- Original inspiration: [Mathias Bynens' dotfiles](https://github.com/mathiasbynens/dotfiles)
- Stow integration: [Cody Reichert's dotfiles](https://github.com/CodyReichert/dotfiles)
- Zsh framework: [Oh-My-Zsh](https://ohmyz.sh/)

## License

MIT License - See [LICENSE-MIT.txt](LICENSE-MIT.txt)
