# Dotfiles

This repo contains my dotfiles and includes a Docker container that builds a simple image which includes [my dotfiles](https://github.com/fredabood/.dotfiles) and [Miniconda3](https://conda.io/miniconda.html) on top of [the latest Ubuntu docker image](https://hub.docker.com/_/ubuntu/).

Most the code in the [Dockerfile](./Dockerfile) is from either [Hamel Husain's Docker tutorial](https://github.com/hamelsmu/Docker_Tutorial/blob/master/basic_tutorial/Dockerfile) or from [Continuum's Miniconda3 image](https://hub.docker.com/r/continuumio/miniconda3/).

My dotfiles were forked from [Mathias Bynen's Dotfiles](https://github.com/mathiasbynens/dotfiles) and modified (with inspiration from [Cody Reichert](https://github.com/CodyReichert/dotfiles/blob/master/install.sh)) to use stow instead of rsync. I also added an automatic installation of Miniconda3 into the $HOME/.conda directory.

## Installation

**Warning:** If you want to give these dotfiles a try, you should first fork this repository, review the code, and remove things you don’t want or need. Don’t blindly use my settings unless you know what that entails. Use at your own risk!

### Local Dotfiles
To install simply navigate to the directory where you wish to keep the repository, and run:
```bash
git clone https://gitlab.com/fredabood/dotfiles.git && cd .dotfiles && bash bootstrap.sh
```
Uninstall is equally simple. Simply run the command below from inside the repo.
```bash
stow -D home -t $HOME
```

### Building the Docker Container
I keep my projects in a direcotry named Projects in my home directory. If you want to mount a different folder to the Docker container, replace ~/Projects with the path to your folder in the `docker run` command.
```bash
git clone https://gitlab.com/fredabood/dotfiles.git && cd .dotfiles && \
docker build -t dotconda -f ./Dockerfile ./ && \
docker run -it -p 8888:8888 -v ~/Projects/:/root/projects dotconda && \
jupyter notebook --ip 0.0.0.0 --no-browser --allow-root
```

## Environments for Python Versions
Installed from the yml files included in [./hom/envs](./home/envs)
```bash
python -m ipykernel install --user --display-name "Python [root]"

conda env create -f ./home/envs/py27.yml
source activate py27
python -m ipykernel install --user --name py27 --display-name "Python [py27]"
source deactivate

# Create Python 3.6 environment & install Jupyter kernel
conda env create -f ./home/envs/py36.yml
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
