#!/usr/bin/env bash
cd "$(dirname "${BASH_SOURCE}")";

git pull origin master;

bash packages.sh

# Taken from https://github.com/CodyReichert/dotfiles/blob/master/install.sh
for d in `ls .`;
do
    ( stow $d )
done

source $HOME/.bash_profile

# Personal Git Config
git config --global user.name "Fred Abood";
git config --global user.email fred@fredabood.com;

if [ ! -d "$HOME/conda/.conda" ]; then
  bash conda.sh
fi

if [ ! -f "$HOME/.ssh/id_rsa" ]; then
  bash ssh.sh
fi
