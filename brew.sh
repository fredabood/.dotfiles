#!/usr/bin/env bash
KERNEL=$(uname -a)

if [ "${KERNEL:0:5}" = "Linux" ]; then
  sudo apt-get update -y
  sudo apt-get upgrade -y
  sudo apt install python-pip -y
  apt-get --no-install-recommends -yqq install \
    bash-completion \
    build-essential \
    cmake \
    libcurl4  \
    libcurl4-openssl-dev  \
    libssl-dev  \
    libxml2 \
    libxml2-dev  \
    libssl1.1 \
    pkg-config \
    ca-certificates \
    xclip

elif [ "${KERNEL:0:6}" = "Darwin" ]; then
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
  brew install homebrew/php/php56 --with-gmp

  # Install font tools.
  brew tap bramstein/webfonttools
  brew install sfnt2woff
  brew install sfnt2woff-zopfli
  brew install woff2

  # Install some CTF tools; see https://github.com/ctfs/write-ups.
  brew install bfg
  brew install binutils

  # Install other useful binaries.
  brew install ack
  brew install git
  brew install git-lfs
  brew install p7zip
  brew install ssh-copy-id
  brew install tree

  # used for Jupyter R & JS kernels
  brew install cask
  brew cask install xquartz
  brew tap homebrew/science
  brew install r

  brew install pkg-config

  # Install/Update Node/NPM
  brew install node
  npm install npm -g
  npm update -g
  brew install zeromq

  # Install SQL
  brew install mongodb --devel
  brew install mysql
  brew install postgresql
  brew install sqlite3

  # Installing Software
  brew cask install google-chrome
  brew cask install spotify
  brew cask install slack
  brew install lastpass-cli --with-pinentry
  brew cask install virtualbox
  brew cask install vlc
  brew cask install iterm2
  brew cask install atom
  apm install atom-ide-ui \
              ide-python ide-r ide-typescript \
              hydrogen hydrogen-launcher \
              git-plus git-time-machine split-diff \
              platformio-ide-terminal \
              highlight-line \
              tablr \
              pretty-json

  # Remove outdated versions from the cellar.
  brew cleanup

fi
