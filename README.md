# Dotfiles

My dotfiles were forked from [Mathias' Dotfiles](https://github.com/mathiasbynens/dotfiles) and modified (with inspiration from [Cody Reichert](https://github.com/CodyReichert/dotfiles/blob/master/install.sh)) to use stow instead of rsync so they can be modified within the git repo without rerunning the `[bootstrap.sh](./bootstrap.sh)`. I added an automatic installation of the latest version of [Miniconda](https://repo.continuum.io/miniconda/) to the $HOME/.conda directory.

This repo also includes a [Dockerfile](./Dockerfile) that builds a simple image which includes [these dotfiles](https://github.com/fredabood/.dotfiles) and [Miniconda](https://conda.io/miniconda.html) on top of [the latest Ubuntu image](https://hub.docker.com/_/ubuntu/).

Most the code in the Dockerfile is from [Hamel Husain's Docker tutorial](https://github.com/hamelsmu/Docker_Tutorial/blob/master/basic_tutorial/Dockerfile) and [Continuum's Miniconda3 image](https://hub.docker.com/r/continuumio/miniconda3/).

## Installation

**Warning:** If you want to give these dotfiles a try, you should first fork this repository, review the code, and remove things you don’t want or need. Don’t blindly use my settings unless you know what that entails. Use at your own risk!

### Local Dotfiles

To install simply navigate to the directory where you wish to keep the repository, and run:

```bash
git clone https://github.com/fredabood/.dotfiles.git $HOME/.dotfiles && \
cd $HOME/.dotfiles && \
bash bootstrap.sh
```

### Building the Docker Container

I keep my projects in a direcotry named Projects in my home directory. If you want to mount a different folder to the Docker container, replace ~/Projects with the path to your folder in the `docker run` command.

```bash
git clone https://github.com/fredabood/.dotfiles.git $HOME/.dotfiles && \
cd $HOME/.dotfiles && \
docker build -t dotconda -f ./Dockerfile ./ && \
docker run -it -p 8888:8888 -v ~/Projects/:/root/projects dotconda && \
jupyter notebook --ip 0.0.0.0 --no-browser --allow-root
```

## Conda Environments

Installed from the yml files included in [./hom/envs](./home/envs).

```bash
python -m ipykernel install --user --display-name "Python [root]"

conda env create -f ./home/envs/py27.yml
source activate py27
python -m ipykernel install --user --name py27 --display-name "Python [2.7]"
source deactivate

# Create Python 3.6 environment & install Jupyter kernel
conda env create -f ./home/envs/py37.yml
source activate py37
python -m ipykernel install --user --name py37 --display-name "Python [3.7]"
source deactivate
```
