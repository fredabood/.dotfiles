# Troubleshooting Guide

Common issues and solutions for the dotfiles installation and usage.

## Table of Contents

- [Installation Issues](#installation-issues)
- [Zsh and Oh-My-Zsh Issues](#zsh-and-oh-my-zsh-issues)
- [VS Code Issues](#vs-code-issues)
- [Homebrew Issues](#homebrew-issues)
- [Symlink Issues](#symlink-issues)
- [macOS Settings Issues](#macos-settings-issues)
- [Performance Issues](#performance-issues)
- [Git Issues](#git-issues)
- [Claude Code Issues](#claude-code-issues)

---

## Installation Issues

### Issue: Permission Denied When Running install.sh

**Symptom:**
```bash
-bash: ./install.sh: Permission denied
```

**Solution:**
```bash
chmod +x install.sh
./install.sh
```

### Issue: install.sh Fails with "Command Not Found"

**Symptom:**
```bash
install.sh: line 42: brew: command not found
```

**Solution:**

This usually means Homebrew isn't in your PATH. Try:

```bash
# For Intel Macs
export PATH="/usr/local/bin:$PATH"

# For Apple Silicon Macs
export PATH="/opt/homebrew/bin:$PATH"

# Then re-run
./install.sh
```

### Issue: Git Clone Fails

**Symptom:**
```bash
fatal: could not create work tree dir '.dotfiles': Permission denied
```

**Solution:**

1. Check you have write permissions to the target directory:
```bash
ls -la ~
```

2. Try cloning to a different location:
```bash
git clone https://github.com/fredabood/.dotfiles.git ~/Documents/dotfiles
```

### Issue: Installation Hangs or Freezes

**Symptom:**
Installation script stops responding during package installation.

**Solution:**

1. Check your internet connection
2. Cancel (Ctrl+C) and try again
3. Install Homebrew packages manually:
```bash
cd ~/.dotfiles
brew bundle --file=brew/Brewfile --verbose
```

---

## Zsh and Oh-My-Zsh Issues

### Issue: Zsh Not Set as Default Shell

**Symptom:**
Terminal still opens bash instead of zsh.

**Solution:**

```bash
# Check current shell
echo $SHELL

# If it's not /bin/zsh, change it
chsh -s /bin/zsh

# Restart terminal
```

### Issue: Oh-My-Zsh Not Loading

**Symptom:**
```bash
zsh: command not found: omz
```

**Solution:**

1. Verify oh-my-zsh is installed:
```bash
ls -la ~/.oh-my-zsh
```

2. If not installed, install it:
```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

3. Check .zshrc sources oh-my-zsh:
```bash
grep "oh-my-zsh.sh" ~/.zshrc
```

### Issue: Custom Aliases Not Working

**Symptom:**
```bash
zsh: command not found: cleanup
```

**Solution:**

1. Check if aliases.zsh is being sourced:
```bash
grep "aliases.zsh" ~/.zshrc
```

2. Manually source it to test:
```bash
source ~/.dotfiles/zsh/aliases.zsh
```

3. Reload zsh:
```bash
exec zsh
```

### Issue: Plugin Errors on Startup

**Symptom:**
```bash
[oh-my-zsh] plugin 'zsh-autosuggestions' not found
```

**Solution:**

The plugin isn't installed. Install it:

```bash
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
```

Then reload:
```bash
exec zsh
```

### Issue: PATH Not Set Correctly

**Symptom:**
Commands like `python`, `node`, or custom scripts not found.

**Solution:**

1. Check if path.zsh is being sourced:
```bash
echo $PATH
```

2. Verify path.zsh content:
```bash
cat ~/.dotfiles/zsh/path.zsh
```

3. Source it manually to test:
```bash
source ~/.dotfiles/zsh/path.zsh
echo $PATH
```

### Issue: Slow Zsh Startup

**Symptom:**
Terminal takes several seconds to open.

**Solution:**

1. Profile your zsh startup:
```bash
time zsh -i -c exit
```

2. Check for slow plugins. Edit `.zshrc` and disable plugins one by one

3. Common culprits:
   - nvm (use lazy loading)
   - conda (disable auto-activate)
   - Git status in large repositories

4. Use lazy loading for heavy tools:
```zsh
# In ~/.zshrc.local
# Lazy load nvm
load_nvm() {
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
}
```

---

## VS Code Issues

### Issue: VS Code Settings Not Syncing

**Symptom:**
Changes in VS Code don't appear in `~/.dotfiles/vscode/settings.json`

**Solution:**

Check if the settings file is symlinked correctly:

```bash
ls -la ~/Library/Application\ Support/Code/User/settings.json

# Should show: settings.json -> /Users/yourusername/.dotfiles/vscode/settings.json
```

If not symlinked, create it:
```bash
rm ~/Library/Application\ Support/Code/User/settings.json
ln -sf ~/.dotfiles/vscode/settings.json ~/Library/Application\ Support/Code/User/settings.json
```

### Issue: "code" Command Not Found

**Symptom:**
```bash
zsh: command not found: code
```

**Solution:**

1. Install the VS Code command line tools:
   - Open VS Code
   - Press `Cmd+Shift+P`
   - Type: "Shell Command: Install 'code' command in PATH"
   - Select it

2. Verify:
```bash
which code
# Should output: /usr/local/bin/code
```

### Issue: Extensions Won't Install

**Symptom:**
```bash
./vscode/install-extensions.sh fails
```

**Solutions:**

1. Ensure VS Code CLI is installed (see above)

2. Try installing extensions manually:
```bash
code --install-extension ms-python.python
```

3. Check VS Code extension marketplace connectivity:
   - Open VS Code
   - Try installing an extension through the GUI

4. Install extensions one by one:
```bash
while IFS= read -r extension; do
    echo "Installing: $extension"
    code --install-extension "$extension" || echo "Failed: $extension"
done < ~/.dotfiles/vscode/extensions.txt
```

### Issue: Snippets Not Working

**Symptom:**
Custom snippets don't appear in VS Code.

**Solution:**

1. Check symlink:
```bash
ls -la ~/Library/Application\ Support/Code/User/snippets
```

2. Recreate symlink if needed:
```bash
rm -rf ~/Library/Application\ Support/Code/User/snippets
ln -sf ~/.dotfiles/vscode/snippets ~/Library/Application\ Support/Code/User/snippets
```

3. Reload VS Code

### Issue: sync-vscode.sh Fails

**Symptom:**
```bash
Error: VS Code settings directory not found
```

**Solution:**

VS Code hasn't been run yet. Open VS Code at least once to create the settings directory, then run the sync script again.

---

## Homebrew Issues

### Issue: Homebrew Not Found After Installation

**Symptom:**
```bash
brew: command not found
```

**Solution:**

Add Homebrew to your PATH:

```bash
# For Apple Silicon Macs
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshrc

# For Intel Macs
echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zshrc

# Reload
exec zsh
```

### Issue: Brew Bundle Fails

**Symptom:**
```bash
Error: No available formula or cask with the name "package-name"
```

**Solutions:**

1. Update Homebrew:
```bash
brew update
```

2. Check if package name changed:
```bash
brew search package-name
```

3. Comment out the failing package in Brewfile and continue:
```bash
nano ~/.dotfiles/brew/Brewfile
# Add # before the failing package
```

4. Try installing packages individually:
```bash
brew install git
brew install vim
# etc.
```

### Issue: Cask Installation Fails

**Symptom:**
```bash
Error: Cask 'visual-studio-code' is already installed
```

**Solution:**

This is actually fine - it means the app is already installed. If you want to reinstall:

```bash
brew reinstall --cask visual-studio-code
```

---

## Symlink Issues

### Issue: Symlinks Point to Wrong Location

**Symptom:**
```bash
ls -la ~/.zshrc
# Shows: .zshrc -> /wrong/path/.dotfiles/zsh/.zshrc
```

**Solution:**

Remove and recreate symlinks:

```bash
cd ~/.dotfiles
rm ~/.zshrc
ln -sf ~/.dotfiles/zsh/.zshrc ~/.zshrc
```

### Issue: Can't Edit Symlinked Files

**Symptom:**
Editing `~/.zshrc` doesn't seem to work or changes are lost.

**Solution:**

This is expected behavior. When files are symlinked:

1. Edit the file in the dotfiles repo:
```bash
nano ~/.dotfiles/zsh/.zshrc
```

2. Or edit the symlinked file (it will update the source):
```bash
nano ~/.zshrc
# This actually edits ~/.dotfiles/zsh/.zshrc
```

3. Reload:
```bash
exec zsh
```

### Issue: Broken Symlinks

**Symptom:**
```bash
ls: ~/.zshrc: No such file or directory
```

**Solution:**

1. Find broken symlinks:
```bash
find ~ -maxdepth 1 -type l ! -exec test -e {} \; -print
```

2. Remove broken symlinks:
```bash
rm ~/.zshrc
```

3. Recreate from dotfiles:
```bash
cd ~/.dotfiles
./install.sh
```

---

## macOS Settings Issues

### Issue: defaults.sh Changes Don't Take Effect

**Symptom:**
Running `macos/defaults.sh` but settings don't change.

**Solution:**

1. Many settings require logging out or restarting:
```bash
killall Finder
killall Dock
killall SystemUIServer
```

2. Some settings require a full restart:
```bash
sudo shutdown -r now
```

3. Check if the setting is correct:
```bash
defaults read com.apple.finder ShowHidden Files
```

### Issue: Permission Denied Running defaults.sh

**Symptom:**
```bash
defaults write: permission denied
```

**Solution:**

The script needs sudo for some commands:

```bash
sudo ./macos/defaults.sh
```

### Issue: Want to Undo macOS Settings

**Symptom:**
Don't like the changes made by defaults.sh.

**Solution:**

1. Restore individual settings:
```bash
# Example: restore hidden files behavior
defaults write com.apple.finder AppleShowAllFiles -bool false
killall Finder
```

2. Reset to defaults:
```bash
defaults delete com.apple.finder
killall Finder
```

---

## Performance Issues

### Issue: Terminal Startup is Slow

**Solutions:**

1. Profile your startup time:
```bash
time zsh -i -c exit
```

2. Disable plugins temporarily to find the culprit:
```bash
# Edit ~/.dotfiles/zsh/.zshrc
# Comment out plugins one by one
```

3. Common performance improvements:
   - Disable unused oh-my-zsh plugins
   - Use lazy loading for nvm, pyenv, rbenv
   - Disable git status in large repos
   - Clear history file if very large

4. Benchmark individual components:
```bash
time source ~/.dotfiles/zsh/aliases.zsh
time source ~/.dotfiles/zsh/functions.zsh
```

### Issue: VS Code Slow to Start

**Solutions:**

1. Too many extensions. Review and disable unused ones:
```bash
cat ~/.dotfiles/vscode/extensions.txt
# Comment out extensions you don't use
```

2. Clear VS Code cache:
```bash
rm -rf ~/Library/Application\ Support/Code/Cache
rm -rf ~/Library/Application\ Support/Code/CachedData
```

---

## Git Issues

### Issue: Git Config Not Loading

**Symptom:**
Git doesn't recognize your name/email.

**Solution:**

1. Check if gitconfig is symlinked:
```bash
ls -la ~/.gitconfig
```

2. Verify content:
```bash
cat ~/.dotfiles/git/.gitconfig
```

3. Set manually:
```bash
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

### Issue: Global Gitignore Not Working

**Symptom:**
Files that should be ignored are still tracked.

**Solution:**

1. Check gitignore is configured:
```bash
git config --global core.excludesfile
# Should output: /Users/yourusername/.gitignore_global
```

2. Set it manually:
```bash
git config --global core.excludesfile ~/.gitignore_global
```

3. Verify the symlink:
```bash
ls -la ~/.gitignore_global
```

---

## Claude Code Issues

Start with the health check; it names the problem:

```bash
~/.dotfiles/claude/install.sh --status
~/.dotfiles/claude/scripts/claude-settings status
```

### Issue: A skill, agent or command is missing

**Cause:** an item was added to `claude/` without re-running the linker, or a third-party installer
replaced a managed link with a real directory (`--status` reports "not a link").

**Solution:**
```bash
~/.dotfiles/claude/install.sh     # backs the real copy up to ~/.claude-migration-backup/ and relinks
```

### Issue: A session says "Claude settings sync needs attention"

That warning comes from the `SessionStart` hook (`claude/hooks/claude-settings-sync.sh`), which
normally syncs `settings.json` silently. It only speaks when `claude-settings sync` refused, and it
left `settings.json` untouched. The reason is in the warning and in
`~/.local/state/dotfiles/claude-settings-sync.log`; it is one of the two issues below. Once
resolved, the next session is silent again.

### Issue: "live settings.json drifted" / "removes or rewrites something settings.base.json defines"

**Cause:** Claude Code changed `~/.claude/settings.json` in a way the private overlay cannot hold —
usually removing a permission or hook the public base defines.

**Solution:** inspect, then pick a side:
```bash
~/.dotfiles/claude/scripts/claude-settings diff
# keep the removal: edit claude/settings.base.json, then
~/.dotfiles/claude/scripts/claude-settings sync
# or discard live's change (live is backed up first):
~/.dotfiles/claude/scripts/claude-settings apply --force
```

### Issue: "CONFLICT" or "no generation record and live settings.json differs"

**Cause:** live settings changed **and** the base or overlay changed since the last generation
(e.g. pulled on another machine) — or Claude Code ran before the installer on a fresh Mac.

**Solution:** `claude-settings diff`, then `claude-settings absorb --force` (live wins; the old
overlay is backed up) followed by `claude-settings apply`, or `claude-settings apply --force`
(generated wins; live is backed up). Commit the overlay in the vault afterwards.

### Issue: A Claude Code update stops loading linked skills

**Solution:** switch to real copies until it is fixed, then relink:
```bash
~/.dotfiles/claude/install.sh --materialize
# later
~/.dotfiles/claude/install.sh
```

### Issue: Commit blocked by `check-public`

**Cause:** gitleaks found a credential, or a staged change matched the private denylist in the
vault (`personal/claude/denylist.txt`) — a hostname, internal domain, client name or address.

**Solution:** move the value out of the repo (personal facts → the vault's `personal/profile.md`;
private settings → the overlay) and re-stage. If gitleaks is missing: `brew install gitleaks`.

---

## Still Having Issues?

If you're still experiencing problems:

1. **Check the [FAQ](FAQ.md)** for more answers
2. **Review [Setup Guide](SETUP.md)** to ensure correct installation
3. **Enable debug mode**:
   ```bash
   # Add to ~/.zshrc.local
   set -x  # Enable debugging
   ```
   Then check what's being executed

4. **Create a minimal test**:
   ```bash
   # Start a fresh zsh without loading dotfiles
   zsh -f

   # Manually source components
   source ~/.dotfiles/zsh/.zshenv
   source ~/.dotfiles/zsh/path.zsh
   ```

5. **Check system logs**:
   ```bash
   # macOS logs
   log show --predicate 'process == "zsh"' --last 1h
   ```

6. **Open an issue on GitHub** with:
   - macOS version: `sw_vers`
   - Zsh version: `zsh --version`
   - Error messages
   - Steps to reproduce
   - What you've already tried

---

## Preventive Measures

To avoid issues in the future:

1. **Keep backups**: The installer creates timestamped backups - don't delete them immediately
2. **Test changes**: Before committing, test configuration changes in a new terminal window
3. **Regular updates**: Keep oh-my-zsh, Homebrew, and dotfiles updated
4. **Version control**: Commit changes frequently so you can rollback if needed
5. **Document customizations**: Add comments to your local modifications

```bash
# In ~/.zshrc.local
# Added 2025-01-04 - Custom work directory shortcut
alias work="cd ~/work/projects"
```
