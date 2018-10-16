#!/usr/bin/env bash

# In order to use the rsync function instead of stow, cd into the home directory
cd "$(dirname "${BASH_SOURCE}")";

git pull origin master;


KERNEL=$(uname -a)
if [ "${KERNEL:0:5}" = "Linux" ]; then
	sudo apt-get install stow -y
elif [ "${KERNEL:0:6}" = "Darwin" ]; then
  brew install stow
fi
unset KERNEL

function doIt() {
	for file in `ls -a ./home/`; do
	  if [ -r "$HOME/$file" ] && [ -f "$HOME/$file" ]; then
	    rm $HOME/$file
	  elif [ -r "$HOME/$file" ] && [ -d "$HOME/$file" ] && [ $file != "." ] && [ $file != ".." ]; then
	    rm -r $HOME/$file
	  fi
	done
	unset file
	( stow -R home -t $HOME )
	source $HOME/.bash_profile;
}

# function doIt() {
# 	rsync --exclude ".git/" \
# 		--exclude ".DS_Store" \
# 		--exclude ".osx" \
# 		--exclude "bootstrap.sh" \
# 		--exclude "README.md" \
# 		--exclude "LICENSE-MIT.txt" \
# 		--exclude "brew.sh" \
# 		--exclude "conda.sh" \
# 		-avh --no-perms . ~;
# 	source $HOME/.bash_profile;
# }

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

# Personal Git Config
git config --global user.name "Fred Abood";
git config --global user.email fred@fredabood.com;
git config --global --unset commit.gpgsign;

source $HOME/.bash_profile
