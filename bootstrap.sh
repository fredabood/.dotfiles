#!/usr/bin/env bash

# In order to use the rsync function instead of stow, cd into the home directory
cd "$(dirname "${BASH_SOURCE}")";

git pull origin master;

bash brew.sh;

function doIt() {
	for file in `ls -a ./home/`; do
	  if [ -r "$HOME/$file" ] && [ -f "$HOME/$file" ]; then
	    rm $HOME/$file
	  elif [ -r "$HOME/$file" ] && [ -d "$HOME/$file" ] && [ $file != "." ] && [ $file != ".." ]; then
	    rm -r $HOME/$file
	  fi
	done
	unset file
	( stow -R home )
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

bash conda.sh

# Personal Git Config
git config --global user.name "Fred Abood";
git config --global user.email fred@fredabood.com;
git config --global --unset commit.gpgsign;

if [ ! -f "$HOME/.ssh/id_rsa" ]; then
  ssh-keygen -f $HOME/.ssh/id_rsa -t rsa -b 4096 -C "fred@fredabood.com";
  echo "
  Host github.com
    HostName github.com
    User git
    IdentityFile $HOME/.ssh/id_rsa
  Host gitlab.com
    HostName gitlab.com
    User git
    PubkeyAuthentication yes
    IdentityFile $HOME/.ssh/id_rsa
  Host nu.bootcampcontent.com
    HostName nu.bootcampcontent.com
    User git
    IdentityFile $HOME/.ssh/id_rsa
  " >> ~/.ssh/config
fi

source $HOME/.bash_profile
