#!/usr/bin/env bash
mkdir $HOME/.dotfiles

cd "$(dirname "${BASH_SOURCE}")";

git pull origin master;

function doIt() {
	rsync --exclude ".git/" \
		--exclude ".DS_Store" \
		--exclude ".osx" \
		--exclude "bootstrap.sh" \
		--exclude "atom.sh" \
		--exclude "conda.sh" \
		--exclude "remote.sh" \
		--exclude "brew.sh" \
		--exclude "README.md" \
		--exclude "LICENSE-MIT.txt" \
		-avh --no-perms . $HOME/.dotfiles;
	source ~/.bash_profile;
}

if [ "$1" == "--force" -o "$1" == "-f" ]; then
	doIt;
else
	read -p "This may overwrite existing files in your home directory. Are you sure? (y/n) " -n 1;
	echo "";
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		doIt;
	fi;
fi;
unset doIt;

KERNEL=$(uname -a)
if [ "${KERNEL:0:6}" = "Darwin" ]; then
  xcode-select --install
  bash ./conda.sh
	bash ./brew.sh
  bash ./atom.sh
elif [ "${KERNEL:0:5}" = "Linux" ]; then
  bash ./conda.sh
  bash ./remote.sh
fi

cd $HOME && stow -R $HOME/.dotfiles;
