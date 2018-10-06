#!/usr/bin/env bash
cd "$(dirname "${BASH_SOURCE}")";

git pull origin master;

KERNEL=$(uname -a)
if [ "${KERNEL:0:6}" = "Darwin" ]; then
  bash packages.sh
elif [ "${KERNEL:0:5}" = "Linux" ]; then
  sudo apt-get update && \
  sudo apt-get upgrade && \
  sudo apt-get install -y stow && \
  sudo apt install python-pip
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

KERNEL=$(uname -a)
if [ "${KERNEL:0:6}" = "Darwin" ]; then
  bash local.sh
elif [ "${KERNEL:0:5}" = "Linux" ]; then
  bash remote.sh
fi

# Personal Git Config
git config --global user.name "Fred Abood";
git config --global user.email fred@fredabood.com;
