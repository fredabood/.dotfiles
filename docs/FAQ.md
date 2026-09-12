# Frequently Asked Questions (FAQ)

Common questions about the dotfiles repository.

## Table of Contents

- [General Questions](#general-questions)
- [Installation & Setup](#installation--setup)
- [Configuration & Customization](#configuration--customization)
- [VS Code](#vs-code)
- [Multiple Machines](#multiple-machines)
- [Updating & Maintenance](#updating--maintenance)
- [Security & Privacy](#security--privacy)

---

## General Questions

### What are dotfiles?

Dotfiles are configuration files for Unix-like systems (macOS, Linux) that typically start with a dot (`.`), making them hidden by default. They configure your shell, editor, git, and other command-line tools.

### Why should I use a dotfiles repository?

**Benefits:**
- **Consistency** across multiple machines
- **Version control** for your configurations
- **Easy backup** and restoration
- **Quick setup** of new machines
- **Share** configurations with team members
- **Document** your workflow

### Is this repository only for macOS?

Yes, this repository is specifically designed and tested for macOS. While many components might work on Linux, the installation scripts and macOS-specific settings are tailored for Apple's operating system.

### Do I need programming knowledge to use this?

Not necessarily, but basic command-line familiarity is helpful. The installation script is interactive and guides you through the process. However, understanding shell scripting basics will help you customize the configuration.

### Can I use parts of this without installing everything?

Absolutely! You can:
- Manually symlink only specific config files
- Cherry-pick aliases or functions you like
- Use the Brewfile independently
- Apply only the macOS settings you want

See the [Customization Guide](CUSTOMIZATION.md) for details.

---

## Installation & Setup

### Will this overwrite my existing configuration?

No, the installer creates timestamped backups of any existing configuration files before making changes. Your original files are preserved as `.filename.backup.YYYYMMDD_HHMMSS`.

### Can I try this without committing fully?

Yes! The installation is non-destructive:
1. All original files are backed up
2. Changes are made via symlinks (easily reversible)
3. You can test in a new user account first
4. Uninstallation is straightforward

### How long does installation take?

Typically 5-15 minutes, depending on:
- Internet speed (downloading packages)
- Number of VS Code extensions
- Whether you install optional components

### What if I don't want to install everything?

The installer is interactive and asks for confirmation before each major step. You can:
- Skip Homebrew package installation
- Skip VS Code setup
- Skip macOS system preferences
- Skip oh-my-zsh plugin installation

### Can I install this on a work computer?

Check with your IT department first. Some considerations:
- May require admin privileges
- Changes system preferences
- Installs software packages
- Modifies shell configuration

For work computers, consider:
- Installing only user-level configurations
- Skipping system-wide changes
- Using a separate branch for work-specific settings

---

## Configuration & Customization

### How do I add my own aliases?

**Option 1: Edit the main aliases file**
```bash
nano ~/Repositories/dotfiles/zsh/aliases.zsh
# Add your aliases
git commit -am "Add custom aliases"
```

**Option 2: Use local configuration (recommended for machine-specific aliases)**
```bash
# Create ~/.zshrc.local
echo 'alias myalias="my command"' >> ~/.zshrc.local
```

### How do I change the zsh theme?

Edit `~/Repositories/dotfiles/zsh/.zshrc`:
```bash
nano ~/Repositories/dotfiles/zsh/.zshrc
```

Find the line:
```zsh
ZSH_THEME="robbyrussell"
```

Change to your preferred theme:
```zsh
ZSH_THEME="agnoster"
# or
ZSH_THEME="powerlevel10k/powerlevel10k"
```

Then reload:
```bash
exec zsh
```

### How do I add more Homebrew packages?

Edit the Brewfile:
```bash
nano ~/Repositories/dotfiles/brew/Brewfile
```

Add packages:
```ruby
brew "package-name"
cask "application-name"
```

Install:
```bash
cd ~/Repositories/dotfiles
brew bundle --file=brew/Brewfile
```

### Can I have machine-specific settings?

Yes! Create `~/.zshrc.local`:
```bash
# In ~/.zshrc.local (not tracked in git)
export WORK_DIR="/Users/yourname/work"
alias work="cd $WORK_DIR"

# Machine-specific PATH additions
export PATH="/custom/path:$PATH"
```

This file is sourced by `.zshrc` but not tracked in git.

### How do I disable certain aliases or functions?

**Option 1: Comment them out**
```bash
nano ~/Repositories/dotfiles/zsh/aliases.zsh
# Add # before the alias you want to disable
```

**Option 2: Unalias in your local config**
```bash
# In ~/.zshrc.local
unalias unwanted_alias
```

### What if I prefer bash to zsh?

This repository is zsh-focused, but the deprecated bash configurations are preserved in `deprecated/bash/`. You could:
1. Restore the bash configs from `deprecated/bash/`
2. Adapt the zsh configs for bash (syntax differences exist)
3. Use a different dotfiles repository designed for bash

---

## VS Code

### How does VS Code sync work?

**Automatic sync** (after initial setup):
- `settings.json` is symlinked to `~/Repositories/dotfiles/vscode/`
- Changes in VS Code → automatically update your dotfiles
- Changes in dotfiles → automatically appear in VS Code

**Manual sync** (for extensions):
- Run `./sync-vscode.sh` to update `extensions.txt`
- Commit and push changes

### Do I have to use VS Code?

No, the VS Code integration is optional. You can:
- Skip VS Code setup during installation
- Use Vim (configuration included in `editors/`)
- Use any other editor with `.editorconfig` support

### Will this conflict with VS Code Settings Sync?

These dotfiles use symlinks instead of VS Code's built-in Settings Sync. You should:
- **Disable** VS Code Settings Sync if using this dotfiles approach
- Or **don't use** the VS Code component of these dotfiles

Choose one method, not both.

### How do I sync VS Code to a new machine?

On the new machine, just run:
```bash
cd ~/Repositories/dotfiles
./install.sh
```

The installer will:
1. Symlink settings and keybindings
2. Ask if you want to install extensions
3. Symlink snippets

Everything will match your other machine.

### What if an extension is no longer available?

The extension installer will skip unavailable extensions and continue. Check the output:
```bash
cd ~/Repositories/dotfiles/vscode
./install-extensions.sh
```

Remove unavailable extensions from `extensions.txt`:
```bash
nano ~/Repositories/dotfiles/vscode/extensions.txt
```

---

## Multiple Machines

### How do I keep multiple machines in sync?

**Initial sync:**
```bash
# Machine A (main machine)
cd ~/Repositories/dotfiles
./sync-vscode.sh  # If using VS Code
git push

# Machine B (other machine)
git clone https://github.com/yourusername/.dotfiles.git ~/Repositories/dotfiles
cd ~/Repositories/dotfiles
./install.sh
```

**Ongoing sync:**
```bash
# After making changes on any machine
cd ~/Repositories/dotfiles
git add .
git commit -m "Update configuration"
git push

# On other machines
cd ~/Repositories/dotfiles
git pull
brew bundle --file=brew/Brewfile  # Install any new packages
```

### Should each machine have the same configuration?

Not necessarily! Use `~/.zshrc.local` for machine-specific settings:

```bash
# On work laptop
echo 'export WORK_ENV=true' >> ~/.zshrc.local
echo 'alias vpn="sudo openconnect vpn.company.com"' >> ~/.zshrc.local

# On personal desktop
echo 'export PERSONAL_ENV=true' >> ~/.zshrc.local
echo 'alias nas="ssh user@192.168.1.100"' >> ~/.zshrc.local
```

### Can I have different VS Code extensions per machine?

Yes, but they'll sync if you use the same dotfiles repo. Options:

**Option 1:** Use separate branches
```bash
# On work machine
git checkout work
./sync-vscode.sh
```

**Option 2:** Don't sync extensions
- Edit `extensions.txt` manually to keep common extensions only
- Install machine-specific extensions outside of the dotfiles workflow

**Option 3:** Use machine-specific extension files
- Not currently implemented, but could be added with custom scripting

### What about different macOS versions?

Some macOS settings in `macos/defaults.sh` may not work across different macOS versions. Solutions:

1. **Conditional execution** (modify defaults.sh):
```bash
if [[ $(sw_vers -productVersion) == 13.* ]]; then
    # Ventura-specific settings
fi
```

2. **Comment out** incompatible settings for your macOS version

3. **Test** the script in a safe environment first

---

## Updating & Maintenance

### How do I update my dotfiles?

```bash
cd ~/Repositories/dotfiles
git pull
brew bundle --file=brew/Brewfile  # Update packages
exec zsh  # Reload shell
```

### How often should I sync my VS Code extensions?

Whenever you install or remove extensions:
```bash
cd ~/Repositories/dotfiles
./sync-vscode.sh
git commit -am "Update VS Code extensions"
git push
```

### How do I update oh-my-zsh?

```bash
omz update
```

Or automatically (configured in `.zshrc`):
```zsh
zstyle ':omz:update' mode auto
```

### How do I update Homebrew packages?

```bash
brew update
brew upgrade
```

Or use the Brewfile:
```bash
cd ~/Repositories/dotfiles
brew bundle --file=brew/Brewfile
```

### Should I commit every change?

**Yes, commit:**
- New aliases or functions
- Package additions to Brewfile
- VS Code extension changes
- Editor configuration changes

**No need to commit:**
- Temporary experiments
- Machine-specific tweaks (use ~/.zshrc.local instead)

### How do I see what changed?

```bash
cd ~/Repositories/dotfiles
git status
git diff
```

---

## Security & Privacy

### Is it safe to put my dotfiles on GitHub?

**Generally yes**, but be careful about:

**Don't commit:**
- ❌ API keys or tokens
- ❌ Passwords
- ❌ SSH private keys
- ❌ Personal information (addresses, phone numbers)
- ❌ Work-specific confidential information
- ❌ `.env` files with secrets

**Safe to commit:**
- ✅ Editor preferences
- ✅ Shell aliases and functions
- ✅ Git configuration (without sensitive data)
- ✅ VS Code settings (review first)
- ✅ Package lists

**Review before pushing:**
```bash
git diff
```

### What about my Git username and email?

The default `.gitconfig` should have placeholders. Update with your information:

```bash
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

If concerned about privacy, don't commit the `.gitconfig` file:
```bash
echo ".gitconfig" >> .gitignore
```

### Are there any secrets in VS Code settings?

Review your `settings.json` before committing:
```bash
cat ~/Repositories/dotfiles/vscode/settings.json
```

Look for:
- API tokens
- Server URLs with credentials
- Personal paths that reveal sensitive information

### Can I use a private repository?

Absolutely! In fact, it's recommended if:
- You work with sensitive projects
- You include work-specific configurations
- You prefer privacy

Change the remote:
```bash
cd ~/Repositories/dotfiles
git remote set-url origin git@github.com:yourusername/dotfiles-private.git
```

### How do I remove sensitive data already committed?

If you accidentally committed sensitive data:

1. **Remove from current state:**
```bash
git rm --cached path/to/sensitive/file
git commit -m "Remove sensitive data"
```

2. **Remove from history** (use with caution):
```bash
# This rewrites history!
git filter-branch --force --index-filter \
  'git rm --cached --ignore-unmatch path/to/sensitive/file' \
  --prune-empty --tag-name-filter cat -- --all

# Force push (if already pushed)
git push origin --force --all
```

3. **Rotate any exposed credentials** immediately

4. Consider using [BFG Repo-Cleaner](https://rtyley.github.io/bfg-repo-cleaner/) for easier history cleaning

---

## Advanced Topics

### Can I use this with Docker?

The deprecated `Dockerfile` shows how this was previously done, but it's no longer actively maintained. You could:
- Adapt the Dockerfile for your needs
- Use the install script in a Docker container
- Mount dotfiles as volumes in containers

### Can I automate deployment to multiple machines?

Yes, with Ansible, scripts, or remote commands:

```bash
# Example: Deploy to remote machine via SSH
ssh user@remote-machine "git clone https://github.com/yourusername/.dotfiles.git ~/Repositories/dotfiles && ~/Repositories/dotfiles/install.sh"
```

### How do I contribute improvements?

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

Or open an issue to discuss ideas first.

### Can I use this as a template for my own dotfiles?

Absolutely! This is encouraged. Steps:

1. Fork or copy the repository
2. Remove my personal configurations
3. Add your own
4. Customize to your workflow
5. Update the README with your info

---

## Still Have Questions?

- **Check the [Troubleshooting Guide](TROUBLESHOOTING.md)** for common issues
- **Read the [Setup Guide](SETUP.md)** for installation details
- **See [Customization Guide](CUSTOMIZATION.md)** for personalization options
- **Review [Components Documentation](COMPONENTS.md)** for technical details
- **Open an issue on GitHub** if your question isn't answered

---

## Contributing Questions

Found a question that should be in this FAQ? Please open an issue or submit a pull request!
