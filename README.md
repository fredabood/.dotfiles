# Dotfiles

Forked from [Mathias Bynen's Dotfiles](https://github.com/mathiasbynens/dotfiles) and modified with inspiration from [Cody Reichert](https://github.com/CodyReichert/dotfiles/blob/master/install.sh) to use stow instead of rsync.

## RUN IT!!!

### Install or Update
First navigate to the directory where you store your projects or repositories. Then run:
```bash
git clone https://gitlab.com/fredabood/dotfiles.git && cd dotfiles && bash bootstrap.sh
```

### Brew + Conda Install
```bash
bash brew.sh && bash conda.sh
```

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

#### Deleted
* [.gitattributes](https://github.com/mathiasbynens/dotfiles/blob/master/.gitattributes)
* [.hgignore](https://github.com/mathiasbynens/dotfiles/blob/master/.hgignore)
* [.tmux.conf](https://github.com/mathiasbynens/dotfiles/blob/master/.tmux.conf)

## Useful Python Packages
Without the channels in my [.condarc](./home/.condarc), not all of these can be installed with conda.
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
