#!/usr/bin/env bash
cd "$(dirname "${BASH_SOURCE}")";

git pull origin master;

bash packages.sh

for file in ~/.{path,bash_prompt,exports,aliases,functions,extra}; do
	[ -r "$file" ] && [ -f "$file" ] && rm "$file";
done;
unset file;

# Taken from https://github.com/CodyReichert/dotfiles/blob/master/install.sh
for folder in `ls .`; do
  if [ -d "$folder" ]; then
    for file in `ls -a $folder/`; do
      if [ -f "$HOME/$file" ]; then
        rm ~/$file
      elif [ -d "$HOME/$file" ] && [ $file != "." ] && [ $file != ".." ]; then
        rm -r ~/$file
      fi
    done
    ( stow -R $folder )
  fi
done

# Personal Git Config
git config --global user.name "Fred Abood";
git config --global user.email fred@fredabood.com;

bash conda.sh

if [ ! -f "$HOME/.ssh/id_rsa" ]; then
  bash ssh.sh
fi
