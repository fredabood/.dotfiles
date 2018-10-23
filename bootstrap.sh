#!/usr/bin/env bash

# In order to use the rsync function instead of stow, cd into the home directory
cd "$(dirname "${BASH_SOURCE}")";

git pull origin master;

# Only auto-runs brew.sh if the ~/.bash_profile isn't a symlink
KERNEL=$(uname -a)
if [ ! -L $HOME/.bash_profile ] && [ "${KERNEL:0:6}" = "Darwin" ]; then
	bash brew.sh

	USERNAME=$(git config --global user.name)
	if [ "$USERNAME"="" ]; then
		unset USERNAME
		read -p "What is your Git username i.e. Mona Lisa? " USERNAME
	fi

	EMAIL=$(git config --global user.email)
	if [ "$EMAIL"="" ]; then
		unset EMAIL
		read -p "What is your Git email i.e. name@example.com? " EMAIL
	fi

	git config --global user.name "$USERNAME"; unset USERNAME;
	git config --global user.email "$EMAIL"; unset EMAIL;
	
fi

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

source $HOME/.bash_profile;
