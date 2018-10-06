KERNEL=$(uname -a)

if [ "${KERNEL:0:6}" = "Darwin" ]; then
  wget https://repo.continuum.io/miniconda/Miniconda3-latest-MacOSX-x86_64.sh -O $HOME/miniconda.sh
elif [ "${KERNEL:0:5}" = "Linux" ]; then
  wget https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh -O $HOME/miniconda.sh
fi

if [ -d "$HOME/.dotfiles/data/.conda" ]; then
  rm -r $HOME/.dotfiles/data/.conda
fi

bash $HOME/miniconda.sh -b -p $HOME/.dotfiles/data/.conda
echo export PATH="$HOME/.conda/bin:$PATH" >> $HOME/.extra
rm $HOME/miniconda.sh
cd $HOME/.dotfiles && stow -R data
source $HOME/.bash_profile

pip install --upgrade pip && conda update conda -y && \
conda install jupyter jupyterlab ipykernel \
              numpy pandas pandas-profiling \
              matplotlib seaborn plotly \
              tqdm flask sqlalchemy boto3 -y
