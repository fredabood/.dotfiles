#!/usr/bin/env bash

# In order to use the rsync function instead of stow, cd into the home directory
cd "$(dirname "${BASH_SOURCE}")";

git pull origin master;

# Only auto-runs brew.sh if the ~/.bash_profile isn't a symlink
if [ ! -f /.dockerenv ]; then
	KERNEL=$(uname -a)
	if [ ! -L $HOME/.bash_profile ] && [ "${KERNEL:0:5}" = "Linux" ]; then
		sudo apt-get update -y && \
		sudo apt-get install stow python-pip -y
		curl -fsSL get.docker.com -o get-docker.sh && sh get-docker.sh
		sudo docker pull fredabood/dotfiles

	elif [ ! -L $HOME/.bash_profile ] && [ "${KERNEL:0:6}" = "Darwin" ]; then
		bash brew.sh

	fi
fi

function doIt() {
	for file in `ls -a ./$1/`; do
	  if [ -r "$2/$file" ] && [ $file != "." ] && [ $file != ".." ]; then
			if [ -f "$2/$file" ]; then
				rm $2/$file
			elif [ -d "$2/$file" ]; then
				rm -r $2/$file
			fi
	  fi
	done
	unset file
	( stow -R $1 -t $2 )
	source $HOME/.bash_profile;
}

if [ "$1" == "--force" -o "$1" == "-f" ]; then
	doIt;
else
	read -p "This may overwrite existing files in your home directory. Are you sure? (y/n) " -n 1;
	echo "";
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		doIt home "$HOME"
	fi;
fi;
unset doIt;

source $HOME/.bash_profile;
