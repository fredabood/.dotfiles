#!/usr/bin/env bash

if [ "${KERNEL:0:5}" = "Linux" ]; then
  sudo apt-get update && \
	sudo apt-get upgrade && \
	sudo apt-get install -y stow && \
  sudo apt install python-pip && \
  sudo apt-get install default-jre && \
  sudo apt-get install scala && \

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
  # brew install aircrack-ng
  brew install bfg
  brew install binutils
  # brew install binwalk
  # brew install cifer
  # brew install dex2jar
  # brew install dns2tcp
  # brew install fcrackzip
  # brew install foremost
  # brew install hashpump
  # brew install hydra
  # brew install john
  # brew install knock
  # brew install netpbm
  # brew install nmap
  # brew install pngcheck
  # brew install socat
  # brew install sqlmap
  # brew install tcpflow
  # brew install tcpreplay
  # brew install tcptrace
  # brew install ucspi-tcp # `tcpserver` etc.
  # brew install xpdf
  # brew install xz

  # Install other useful binaries.
  brew install ack
  #brew install exiv2
  brew install git
  brew install git-lfs
  # brew install imagemagick --with-webp
  # brew install lua
  # brew install lynx
  brew install p7zip
  # brew install pigz
  # brew install pv
  # brew install rename
  # brew install rlwrap
  brew install ssh-copy-id
  brew install tree
  # brew install vbindiff
  # brew install zopfli


  brew install stow

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
