# Dotfiles

My fork of [Mathias' Dotfiles](https://github.com/mathiasbynens/dotfiles).

The [./remote.sh](./remote.sh) code came from [Jose Portilla's Tutorial](https://medium.com/@josemarcialportilla/getting-spark-python-and-jupyter-notebook-running-on-amazon-ec2-dec599e1c297).

[Miniconda Archive](https://repo.continuum.io/miniconda/) | [Jupyter Kernels](https://github.com/jupyter/jupyter/wiki/Jupyter-kernels)

### New Files Not Included in Mathias':
* [.condarc](./.condarc)
* [.extra](./.extra)
* [atom.sh](./atom.sh)
* [conda.sh](./conda.sh)
* [init/py27.yml](./init/py27.yml)
* [init/py36.yml](./init/py36.yml)
* [remote.sh](./remote.sh)

### Files Modified From Mathias'
* [.bash_profile](./.bash_profile)
* [.gitignore](./.gitignore)
* [README.md](./README.md)
* [bootstrap.sh](./bootstrap.sh)
* [brew.sh](./brew.sh)
* [init/SolarizedDark.itermcolors](./init/SolarizedDark.itermcolors)

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
              scikit-learn spacy tensorflow keras theano ;

pip install nteract_on_jupyter vaderSentiment;

python -m spacy download en_core_web_sm;
python -m spacy download en_core_web_md;
```
