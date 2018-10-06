#!/usr/bin/env bash
cd "$(dirname "${BASH_SOURCE}")";

git pull origin master;

bash packages.sh

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
