#!/usr/bin/env bash
cd "$(dirname "${BASH_SOURCE}")";

git pull origin master;

KERNEL=$(uname -a)
if [ "${KERNEL:0:6}" = "Darwin" ]; then
  bash brew.sh
elif [ "${KERNEL:0:5}" = "Linux" ]; then
  sudo apt-get update -y
  sudo apt-get upgrade -y
  # sudo apt-get install stow -y
  sudo apt install python-pip -y
fi

# for folder in `ls .`; do
#   if [ -d "$folder" ]; then
#     for file in `ls -a $folder/`; do
#       if [ -r "$HOME/$file" ] && [ -f "$HOME/$file" ]; then
#         rm ~/$file
#       elif [ -r "$HOME/$file" ] && [ -d "$HOME/$file" ] && [ $file != "." ] && [ $file != ".." ]; then
#         rm -r ~/$file
#       fi
#     done
#     unset file
#     ( stow -R $folder )
#   fi
# done
# unset folder

function doIt() {
	rsync --exclude ".git/" \
		--exclude ".DS_Store" \
		--exclude ".osx" \
		--exclude "bootstrap.sh" \
		--exclude "README.md" \
		--exclude "LICENSE-MIT.txt" \
		-avh --no-perms . ~;
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


# # Personal Git Config
# git config --global user.name "Fred Abood";
# git config --global user.email fred@fredabood.com;
# git config --global --unset commit.gpgsign;
#
# if [ ! -f "$HOME/.ssh/id_rsa" ]; then
#   ssh-keygen -f $HOME/.ssh/id_rsa -t rsa -b 4096 -C "fred@fredabood.com";
#   echo "
#   Host github.com
#     HostName github.com
#     User git
#     IdentityFile $HOME/.ssh/id_rsa
#   Host gitlab.com
#     HostName gitlab.com
#     User git
#     PubkeyAuthentication yes
#     IdentityFile $HOME/.ssh/id_rsa
#   Host nu.bootcampcontent.com
#     HostName nu.bootcampcontent.com
#     User git
#     IdentityFile $HOME/.ssh/id_rsa
#   " >> ~/.ssh/config
# fi

source $HOME/.bash_profile
