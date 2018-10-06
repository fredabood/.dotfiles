#!/usr/bin/env bash
cd "$(dirname "${BASH_SOURCE}")";

git pull origin master;

bash packages.sh

# Taken from https://github.com/CodyReichert/dotfiles/blob/master/install.sh
for d in `ls .`;
do
  ( stow $d )
done

source ~/.bash_profile

# Personal Git Config
git config --global user.name "Fred Abood";
git config --global user.email fred@fredabood.com;

bash conda.sh
bash ssh.sh
