# Dotfiles

Forked from [Mathias Bynen's Dotfiles](https://github.com/mathiasbynens/dotfiles) and modified with inspiration from [Cody Reichert](https://github.com/CodyReichert/dotfiles/blob/master/install.sh) to use stow instead of rsync.

### Install Command
```bash
cd $HOME && \
git clone https://gitlab.com/fredabood/dotfiles.git && \
bash bootstrap.sh && \
bash brew.sh && bash conda.sh
```

### New Files Not Included in Mathias':
* [.condarc](./conda/.condarc) - For default conda config
* [conda.sh](./conda.sh) - Miniconda + packages + envs, Spark, Jupyter + kernels
* [init/py27.yml](./bash/init/py27.yml) - For conda env creation
* [init/py36.yml](./bash/init/py36.yml) - For conda env creation

### Files Modified From Mathias'
* [.bash_profile](./bash/.bash_profile) - Tweaked to work with symlinks
* [.gitignore](./.gitignore) - Added .ipynb_checkpoints/* and __pycache__/*
* [README.md](./README.md)
* [bootstrap.sh](./bootstrap.sh)
* [brew.sh](./brew.sh)
* [init/SolarizedDark.itermcolors](./init/SolarizedDark.itermcolors) - Foreground Color = rgb(0.49725341796875, 0.98527109622955322, 1)

### Files Deleted From Mathias'
* [.gitattributes](./.gitattributes)
* [.hgignore](./.hgignore)
* [.tmux.conf](./.tmux.conf)

## Useful Python Packages
```bash
pip install --upgrade pip;
conda update conda;

# If your conda channels don't match mine, not all of these will install with conda.
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
              argcomplete -y

pip install nteract_on_jupyter vaderSentiment;

python -m spacy download en_core_web_sm;
python -m spacy download en_core_web_md;
```

### [Miniconda Archive](https://repo.continuum.io/miniconda/) | [Jupyter Kernels](https://github.com/jupyter/jupyter/wiki/Jupyter-kernels)
