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

source $HOME/.bash_profile
