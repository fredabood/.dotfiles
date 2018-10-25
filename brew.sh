#!/usr/bin/env bash

xcode-select --install

ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
brew tap caskroom/cask
brew tap caskroom/versions

# Install command-line tools using Homebrew.

# Make sure we’re using the latest Homebrew. Upgrade any already-installed formulae.
brew update && brew upgrade

# Save Homebrew’s installed location.
BREW_PREFIX=$(brew --prefix)

# Install GNU core utilities (those that come with macOS are outdated).
# Don’t forget to add `$(brew --prefix coreutils)/libexec/gnubin` to `$PATH`.
brew install coreutils
ln -s "${BREW_PREFIX}/bin/gsha256sum" "${BREW_PREFIX}/bin/sha256sum"

# Install some other useful utilities like `sponge`.
brew install moreutils
# Install GNU `find`, `locate`, `updatedb`, and `xargs`, `g`-prefixed.
brew install findutils
# Install GNU `sed`, overwriting the built-in `sed`.
brew install gnu-sed --with-default-names
# Install Bash 4.
brew install bash
brew install bash-completion2

# Switch to using brew-installed bash as default shell
if ! fgrep -q "${BREW_PREFIX}/bin/bash" /etc/shells; then
  echo "${BREW_PREFIX}/bin/bash" | sudo tee -a /etc/shells;
  chsh -s "${BREW_PREFIX}/bin/bash";
fi;

# Install `wget` with IRI support.
brew install wget --with-iri

# Install GnuPG to enable PGP-signing commits.
brew install gnupg

# Install more recent versions of some macOS tools.
brew install vim --with-override-system-vi
brew install grep
brew install openssh
brew install screen

# Install other useful binaries.
brew install git
brew install git-lfs
brew install p7zip
brew install ssh-copy-id

brew install stow

# Installing Software
brew cask install docker
brew cask install google-chrome
brew cask install spotify
brew cask install slack
brew install lastpass-cli --with-pinentry
brew cask install virtualbox
brew cask install iterm2
brew cask install atom
apm install atom-ide-ui \
            ide-python ide-docker language-docker \
            hydrogen hydrogen-launcher \
            git-time-machine split-diff \
            platformio-ide-terminal \
            highlight-line \
            tablr \
            pretty-json \
            atom-file-icons file-icons

# Remove outdated versions from the cellar.
brew cleanup
