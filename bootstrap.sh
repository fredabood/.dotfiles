#!/usr/bin/env bash
cd "$(dirname "${BASH_SOURCE}")";

git pull origin master;

KERNEL=$(uname -a)
if [ "${KERNEL:0:6}" = "Darwin" ]; then
  bash brew.sh
elif [ "${KERNEL:0:5}" = "Linux" ]; then
  sudo apt-get update -Y && \
  sudo apt-get upgrade -Y && \
  sudo apt-get install stow -Y && \
  sudo apt install python-pip -Y
fi

for folder in `ls .`; do
  if [ -d "$folder" ]; then
    for file in `ls -a $folder/`; do
      if [ -r "$HOME/$file" ] && [ -f "$HOME/$file" ]; then
        rm ~/$file
      elif [ -r "$HOME/$file" ] && [ -d "$HOME/$file" ] && [ $file != "." ] && [ $file != ".." ]; then
        rm -r ~/$file
      fi
    done
    unset file
    ( stow -R $folder )
  fi
done
unset folder

bash conda.sh

# Personal Git Config
git config --global user.name "Fred Abood";
git config --global user.email fred@fredabood.com;

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
