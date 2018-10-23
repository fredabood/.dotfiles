# Dotfiles

Forked from [Mathias Bynen's Dotfiles](https://github.com/mathiasbynens/dotfiles) and modified (with inspiration from [Cody Reichert](https://github.com/CodyReichert/dotfiles/blob/master/install.sh)) to use stow instead of rsync.

## Installation

**Warning:** If you want to give these dotfiles a try, you should first fork this repository, review the code, and remove things you don’t want or need. Don’t blindly use my settings unless you know what that entails. Use at your own risk!

To install simply navigate to the directory where you wish to keep the repository, and run:
```bash
git clone https://gitlab.com/fredabood/dotfiles.git && cd dotfiles && bash bootstrap.sh
```
Uninstall is equally simple. Simply run the command below from inside the repo.
```bash
stow -D home -t $HOME
```
## Environments for Python Versions
```bash
python -m ipykernel install --user --display-name "Python [root]"

conda env create -f $HOME/init/py27.yml
source activate py27
python -m ipykernel install --user --name py27 --display-name "Python [py27]"
source deactivate

# Create Python 3.6 environment & install Jupyter kernel
conda env create -f $HOME/init/py36.yml
source activate py36
python -m ipykernel install --user --name py36 --display-name "Python [py36]"
source deactivate
```

## Useful Python Packages
This list is inclusive of the packages installed in [conda.sh](./conda.sh) plus some others not included in that script. Without the channels in my [.condarc](./home/.condarc), some of these will have to be installed with pip rather than conda.
```bash
pip install --upgrade pip && conda update conda -y;

conda install cython py4j \
              jupyter jupyterlab ipykernel \
              numpy pandas pandas-profileing \
              matplotlib seaborn plotly \
              bokeh dash folium \
              flask django \
              sqlalchemy boto3 tqdm \
              beautifulsoup4 scrapy \
              pandas-datareader quandl \
              praw google-api-python-client tweepy \
              scikit-learn spacy tensorflow keras theano \
              r-essentials mro-base \
              pyzmq nodejs \
              pyspark sparkmagic \
              argcomplete -y

pip install nteract_on_jupyter vaderSentiment;

python -m spacy download en_core_web_sm;
python -m spacy download en_core_web_md;
```

### [Miniconda Archive](https://repo.continuum.io/miniconda/) | [Jupyter Kernels](https://github.com/jupyter/jupyter/wiki/Jupyter-kernels) | [Spark Downloads](https://spark.apache.org/downloads.html)

## Deviations from Mathias
#### New
* [.condarc](./home/.condarc) - For default conda config
* [conda.sh](./conda.sh) - Miniconda + packages + envs, Spark, Jupyter + kernels
* [init/py27.yml](./home/init/py27.yml) - For conda env creation
* [init/py36.yml](./home/init/py36.yml) - For conda env creation

#### Modified
* [.bash_profile](./home/.bash_profile) - Tweaked to work with symlinks
* [.gitignore](./home/.gitignore) - Added .ipynb_checkpoints/* and __pycache__/*
* [README.md](./README.md)
* [bootstrap.sh](./bootstrap.sh)
* [brew.sh](./brew.sh)
* [init/SolarizedDark.itermcolors](./init/SolarizedDark.itermcolors) - Foreground Color = rgb(0.49725341796875, 0.98527109622955322, 1)
* [.functions](./home/.functions) - Added a function that recursively traverses all the folders in the CWD and git pulls in all the repos.

#### Deleted
* [.gitattributes](https://github.com/mathiasbynens/dotfiles/blob/master/.gitattributes)
* [.hgignore](https://github.com/mathiasbynens/dotfiles/blob/master/.hgignore)
* [.tmux.conf](https://github.com/mathiasbynens/dotfiles/blob/master/.tmux.conf)
