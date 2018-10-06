#!/usr/bin/env bash
cd "$(dirname "${BASH_SOURCE}")";

git pull origin master;

# Personal Git Config
git config --global user.name "Fred Abood";
git config --global user.email fred@fredabood.com;

bash packages.sh

# Taken from https://github.com/CodyReichert/dotfiles/blob/master/install.sh
for d in `ls .`;
do
  ( stow $d )
done

bash conda.sh
bash ssh.sh
