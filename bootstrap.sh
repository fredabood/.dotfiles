#!/usr/bin/env bash

# In order to use the rsync function instead of stow, cd into the home directory
cd "$(dirname "${BASH_SOURCE}")";

USERNAME=$(git config --global user.name)
if [ "$USERNAME"="" ]; then
	read -p "What is your Git username i.e. Mona Lisa?" $USERNAME
fi

EMAIL=$(git config --global user.email)
if [ "$EMAIL"="" ]; then
	read -p "What is your Git email i.e. name@example.com?" $EMAIL
fi

git pull origin master;

git config --global user.name "$USERNAME";
git config --global user.email "$EMAIL";
git config --global --unset commit.gpgsign;

# Only auto-runs brew.sh if the ~/.bash_profile isn't a symlink
if [ ! -L $HOME/.bash_profile ]; then
	bash brew.sh
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

# Only auto-runs conda.sh if the ~/.conda direcotry doesn't exist
if [ ! -d $HOME/.conda ]; then
	bash conda.sh
fi

source $HOME/.bash_profile
