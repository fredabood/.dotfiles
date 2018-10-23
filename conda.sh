#!/usr/bin/env bash

KERNEL=$(uname -a)

if [ "${KERNEL:0:6}" = "Darwin" ]; then
  wget https://repo.continuum.io/miniconda/Miniconda3-latest-MacOSX-x86_64.sh -O $HOME/conda.sh
elif [ "${KERNEL:0:5}" = "Linux" ]; then
  wget https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh -O $HOME/conda.sh
fi

bash $HOME/conda.sh -b -p $HOME/.conda && rm $HOME/conda.sh 
source $HOME/.bash_profile

# Installing all packages at once causes a memory overload on a micro EC2 instance
pip install --upgrade pip && conda update conda -y
conda install jupyter jupyterlab ipykernel -y
conda install numpy pandas pandas-profiling matplotlib seaborn -y
conda install flask sqlalchemy flask-sqlalchemy -y
conda install tqdm boto3 -y
conda install cython pyspark -y

if [ "${KERNEL:0:5}" = "Linux" ]; then
  mkdir $HOME/.jupyter/certs && \
  sudo openssl req -x509 -nodes -days 365 -newkey rsa:1024 -keyout $HOME/.jupyter/certs/jupyter_cert.pem -out $HOME/.jupyter/certs/jupyter_cert.pem
