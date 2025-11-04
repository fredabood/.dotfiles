if [ "${KERNEL:0:6}" = "Darwin" ]; then
  wget https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-arm64.sh -O $HOME/conda.sh
elif [ "${KERNEL:0:5}" = "Linux" ]; then
  wget https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh -O $HOME/conda.sh
fi

bash $HOME/conda.sh -b -p $HOME/.conda && rm $HOME/conda.sh
source $HOME/.bash_profile
pip install --upgrade setuptools pip && conda update conda -y

if [ "${KERNEL:0:5}" = "Linux" ]; then
  mkdir $HOME/.jupyter/certs && \
  sudo openssl req -x509 -nodes -days 365 -newkey rsa:1024 -keyout $HOME/.jupyter/certs/jupyter_cert.pem -out $HOME/.jupyter/certs/jupyter_cert.pem
fi
