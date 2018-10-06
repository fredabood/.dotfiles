#!/usr/bin/env bash
# mkdir $HOME/.dotfiles
#
# cd "$(dirname "${BASH_SOURCE}")";

git pull origin master;

# function doIt() {
# 	rsync --exclude ".git/" \
# 		--exclude ".DS_Store" \
# 		--exclude ".osx" \
# 		--exclude "bootstrap.sh" \
# 		--exclude "atom.sh" \
# 		--exclude "conda.sh" \
# 		--exclude "remote.sh" \
# 		--exclude "brew.sh" \
# 		--exclude "README.md" \
# 		--exclude "LICENSE-MIT.txt" \
# 		-avh --no-perms . $HOME/.dotfiles;
# 	source ~/.dotfiles/.bash_profile;
# }
#
# if [ "$1" == "--force" -o "$1" == "-f" ]; then
# 	doIt;
# else
# 	read -p "This may overwrite existing files in your home directory. Are you sure? (y/n) " -n 1;
# 	echo "";
# 	if [[ $REPLY =~ ^[Yy]$ ]]; then
# 		doIt;
# 	fi;
# fi;
# unset doIt;

KERNEL=$(uname -a)
if [ "${KERNEL:0:6}" = "Darwin" ]; then
  xcode-select --install
	bash brew.sh
  bash conda.sh
  bash atom.sh
elif [ "${KERNEL:0:5}" = "Linux" ]; then
	sudo apt-get update && \
	sudo apt-get upgrade && \
	sudo apt-get install -y stow && \
	# sudo apt-get install -y r-base && \
	# sudo apt-get install -y nodejs && \
	sudo apt install python-pip && \
	bash conda.sh && \
	bash remote.sh;
fi

for folder in ./
	do [[ -f $folder ]] && stow $folder
  do [[ -d $folder ]] && stow $folder
done
