#!/usr/bin/env bash

# In order to use the rsync function instead of stow, cd into the home directory
cd "$(dirname "${BASH_SOURCE}")";

git pull origin master;

# Only auto-runs brew.sh if the ~/.bash_profile isn't a symlink
KERNEL=$(uname -a)
ME=$(whoami)
if [ ! -L $HOME/.bash_profile ] && [ "${KERNEL:0:5}" = "Linux" ]; then
	if [ $ME = "root" ]; then
		apt-get update && \
		apt-get install stow python-pip
	else
		sudo apt-get update && \
		sudo apt-get install stow python-pip
	fi

elif [ ! -L $HOME/.bash_profile ] && [ "${KERNEL:0:6}" = "Darwin" ]; then
	bash brew.sh

	USERNAME=$(git config --global user.name)
	if [ "$USERNAME"="" ]; then
		unset USERNAME
		read -p "What is your Git username i.e. Mona Lisa? " USERNAME
	fi

	EMAIL=$(git config --global user.email)
	if [ "$EMAIL"="" ]; then
		unset EMAIL
		read -p "What is your Git email i.e. name@example.com? " EMAIL
	fi

	git config --global user.name "$USERNAME"; unset USERNAME;
	git config --global user.email "$EMAIL"; unset EMAIL;

fi

function doIt() {
	for file in `ls -a ./home/`; do
	  if [ -r "$HOME/$file" ] && [ -f "$HOME/$file" ]; then
	    rm $HOME/$file
	  elif [ -r "$HOME/$file" ] && [ -d "$HOME/$file" ] && [ $file != "." ] && [ $file != ".." ]; then
	    rm -r $HOME/$file
	  fi
	done
	unset file
	( stow -R home -t $HOME )
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

source $HOME/.bash_profile;

# Install Miniconda3 if it's not already installed.
if [ ! -d ~/.conda ]; then

  if [ "${KERNEL:0:6}" = "Darwin" ]; then
    wget https://repo.continuum.io/miniconda/Miniconda3-latest-MacOSX-x86_64.sh -O $HOME/conda.sh
  elif [ "${KERNEL:0:5}" = "Linux" ]; then
    wget https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh -O $HOME/conda.sh
  fi

  bash $HOME/conda.sh -b -p $HOME/.conda && rm $HOME/conda.sh
  source $HOME/.bash_profile

  pip install --upgrade pip && conda update conda -y

  if [ "${KERNEL:0:5}" = "Linux" ]; then
    mkdir $HOME/.jupyter/certs && \
    sudo openssl req -x509 -nodes -days 365 -newkey rsa:1024 -keyout $HOME/.jupyter/certs/jupyter_cert.pem -out $HOME/.jupyter/certs/jupyter_cert.pem
  fi

fi
