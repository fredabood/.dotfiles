# Detailed Setup Guide

This guide provides comprehensive installation instructions for the dotfiles repository.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Step-by-Step Installation](#step-by-step-installation)
- [First-Time Setup](#first-time-setup)
- [Post-Installation](#post-installation)
- [Verification](#verification)
- [Syncing Multiple Machines](#syncing-multiple-machines)

---

## Prerequisites

### Required

- **macOS** - This dotfiles repository is designed specifically for macOS
- **Command Line Tools** - Will be installed automatically if needed
- **Git** - Usually pre-installed on macOS, or installed with Command Line Tools

### Recommended

- **Internet Connection** - For downloading packages and oh-my-zsh
- **Administrator Access** - Some components require sudo privileges
- **VS Code** - If you want to use the VS Code configuration sync

### What Will Be Installed

The installation script will automatically install:

1. **Homebrew** - Package manager for macOS
2. **Oh-My-Zsh** - Zsh framework
3. **Homebrew Packages** - Development tools and utilities (from Brewfile)
4. **Optional Plugins**:
   - zsh-autosuggestions
   - zsh-syntax-highlighting

---

## Quick Start

For experienced users who want to get up and running quickly:

```bash
# Clone the repository
git clone https://github.com/fredabood/.dotfiles.git ~/.dotfiles

# Navigate to the directory
cd ~/.dotfiles

# Run the installation script
./install.sh

# Restart your terminal
exec zsh
```

---

## Step-by-Step Installation

### Step 1: Clone the Repository

Choose a location for your dotfiles. We recommend `~/.dotfiles`:

```bash
# Clone to home directory
git clone https://github.com/fredabood/.dotfiles.git ~/.dotfiles
```

**Alternative locations:**
- `~/dotfiles` (without the dot)
- `~/Documents/dotfiles`
- Any location you prefer (scripts will auto-detect)

### Step 2: Navigate to Directory

```bash
cd ~/.dotfiles
```

### Step 3: Review the Scripts (Recommended)

Before running installation scripts, review what they'll do:

```bash
# Review the main installer
less install.sh

# Review the Brewfile (packages to be installed)
less brew/Brewfile

# Review macOS settings
less macos/defaults.sh

# Review zsh configuration
less zsh/.zshrc
```

### Step 4: Run the Installer

The installer is interactive and will ask for confirmation before making changes:

```bash
./install.sh
```

### Step 5: Follow the Prompts

The installer will walk you through:

1. **Homebrew Installation** - If not already installed
2. **Oh-My-Zsh Installation** - If not already installed
3. **Package Installation** - From Brewfile (you can skip if desired)
4. **Plugin Installation** - zsh-autosuggestions and zsh-syntax-highlighting
5. **Config File Linking** - Symlinks your dotfiles
6. **VS Code Setup** - If vscode/ directory exists
7. **macOS Preferences** - Optional system settings

**Note:** Your existing configuration files will be backed up with timestamps.

### Step 6: Restart Your Terminal

After installation completes:

```bash
# Option 1: Reload zsh in current terminal
exec zsh

# Option 2: Close and reopen Terminal/iTerm
```

---

## First-Time Setup

### Configure Git

If you haven't already, update the git configuration with your details:

```bash
# Edit git config
nano ~/.dotfiles/git/.gitconfig

# Or use git commands
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

### Set Up VS Code Configuration

If this is your first time using VS Code with these dotfiles:

```bash
# Sync your current VS Code config to the repo
./sync-vscode.sh

# Commit the configuration
git add vscode/
git commit -m "Add my VS Code configuration"
```

### Customize for Your Machine

Create a local customization file that won't be tracked in git:

```bash
# Create local zsh customizations
touch ~/.zshrc.local

# Add machine-specific settings
echo 'export CUSTOM_VAR="value"' >> ~/.zshrc.local
echo 'alias work="cd ~/work"' >> ~/.zshrc.local
```

### Enable Oh-My-Zsh Plugins

Edit `~/.dotfiles/zsh/.zshrc` to enable additional plugins:

```bash
nano ~/.dotfiles/zsh/.zshrc
```

Find the `plugins=()` array and add desired plugins:

```zsh
plugins=(
    git
    macos
    brew
    docker
    z
    zsh-autosuggestions
    zsh-syntax-highlighting
)
```

Save and reload:
```bash
exec zsh
```

---

## Post-Installation

### Install VS Code CLI (if using VS Code)

1. Open VS Code
2. Press `Cmd+Shift+P`
3. Type: "Shell Command: Install 'code' command in PATH"
4. Select it

This enables the `code` command in terminal and VS Code extension installation.

### Test Your Setup

```bash
# Test zsh configuration
echo $SHELL
# Should output: /bin/zsh

# Test oh-my-zsh
echo $ZSH
# Should output: /Users/yourusername/.oh-my-zsh

# Test custom aliases
week
# Should output the current week number

# Test custom functions
mkd test_directory
# Should create and enter directory

# Clean up test
cd .. && rmdir test_directory
```

### Install Additional Software

Review the Brewfile and uncomment any additional tools you want:

```bash
nano ~/.dotfiles/brew/Brewfile
```

Then install:

```bash
cd ~/.dotfiles
brew bundle --file=brew/Brewfile
```

### Apply macOS System Preferences (Optional)

**⚠️ Warning:** This will change various macOS settings. Review the script first!

```bash
# Review what will change
less ~/.dotfiles/macos/defaults.sh

# Apply settings
./macos/defaults.sh
```

Some changes require logging out or restarting.

---

## Verification

### Verify Installations

```bash
# Check Homebrew
brew --version

# Check oh-my-zsh
ls ~/.oh-my-zsh

# Check symlinks
ls -la ~ | grep "\.dotfiles"

# Check VS Code (if installed)
code --version
```

### Verify Configuration

```bash
# Check zsh is sourcing dotfiles
echo $PATH
# Should include paths from zsh/path.zsh

# Check aliases are loaded
alias | grep cleanup
# Should show the cleanup alias

# Check functions are loaded
type mkd
# Should show the mkd function
```

### Verify VS Code (if applicable)

```bash
# Check settings symlink
ls -la ~/Library/Application\ Support/Code/User/settings.json
# Should point to ~/.dotfiles/vscode/settings.json

# Check extensions
code --list-extensions
# Should list your installed extensions
```

---

## Syncing Multiple Machines

### Machine A (Initial Setup)

```bash
# On your first machine
cd ~/.dotfiles
./sync-vscode.sh  # If using VS Code
git add .
git commit -m "My dotfiles configuration"
git push origin master
```

### Machine B (New Machine)

```bash
# On your new machine
git clone https://github.com/fredabood/.dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./install.sh
```

The installer will:
- Set up all your configurations
- Symlink all files
- Install VS Code extensions
- Install Homebrew packages

### Keeping Machines in Sync

On any machine, after making changes:

```bash
cd ~/.dotfiles

# If you changed zsh configs, aliases, etc.
git add zsh/
git commit -m "Update zsh configuration"
git push

# If you installed new VS Code extensions
./sync-vscode.sh
git add vscode/
git commit -m "Update VS Code extensions"
git push

# On other machines
git pull
brew bundle --file=brew/Brewfile  # Install any new packages
```

---

## Advanced Installation Options

### Skip Interactive Prompts

If you want to install everything without prompts (use with caution):

```bash
# This is not currently supported, but you can modify install.sh
# to default all ask_yes_no calls to return true
```

### Install Only Specific Components

You can manually symlink only the components you want:

```bash
# Just zsh
ln -sf ~/.dotfiles/zsh/.zshrc ~/.zshrc
ln -sf ~/.dotfiles/zsh/.zshenv ~/.zshenv

# Just vim
ln -sf ~/.dotfiles/editors/.vimrc ~/.vimrc

# Just git
ln -sf ~/.dotfiles/git/.gitconfig ~/.gitconfig
```

### Custom Installation Location

If you cloned to a different location, the scripts will auto-detect:

```bash
# Clone anywhere
git clone https://github.com/fredabood/.dotfiles.git ~/my-custom-location

# Scripts will work from any location
cd ~/my-custom-location
./install.sh
```

---

## Uninstallation

If you want to remove the dotfiles:

### 1. Remove Symlinks

```bash
# Remove zsh config
rm ~/.zshrc ~/.zshenv

# Remove editor configs
rm ~/.vimrc ~/.editorconfig

# Remove git config
rm ~/.gitconfig ~/.gitignore_global

# Remove VS Code symlinks
rm ~/Library/Application\ Support/Code/User/settings.json
rm ~/Library/Application\ Support/Code/User/keybindings.json
```

### 2. Restore Backups

The installer creates timestamped backups. Find and restore them:

```bash
ls -la ~ | grep backup
# Example: .zshrc.backup.20250104_103045

# Restore
mv ~/.zshrc.backup.20250104_103045 ~/.zshrc
```

### 3. Remove Repository

```bash
rm -rf ~/.dotfiles
```

### 4. Uninstall Oh-My-Zsh (Optional)

```bash
uninstall_oh_my_zsh
```

---

## Next Steps

After installation:

1. **Read the [Customization Guide](CUSTOMIZATION.md)** - Learn how to personalize your setup
2. **Check the [Components Documentation](COMPONENTS.md)** - Understand what each component does
3. **Review [Troubleshooting](TROUBLESHOOTING.md)** - If you encounter any issues
4. **See the [FAQ](FAQ.md)** - Answers to common questions

---

## Getting Help

If you encounter issues:

1. Check the [Troubleshooting Guide](TROUBLESHOOTING.md)
2. Review the [FAQ](FAQ.md)
3. Check your setup with the verification steps above
4. Open an issue on GitHub with details about:
   - Your macOS version
   - Error messages
   - Steps to reproduce

---

## Additional Resources

- [Oh-My-Zsh Documentation](https://github.com/ohmyzsh/ohmyzsh/wiki)
- [Homebrew Documentation](https://docs.brew.sh/)
- [VS Code Settings Sync](https://code.visualstudio.com/docs/editor/settings-sync)
- [macOS Defaults Commands](https://macos-defaults.com/)
