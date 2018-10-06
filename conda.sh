KERNEL=$(uname -a)
if [ "${KERNEL:0:6}" = "Darwin" ]; then
  wget https://repo.continuum.io/miniconda/Miniconda3-latest-MacOSX-x86_64.sh -O $HOME/miniconda.sh
elif [ "${KERNEL:0:5}" = "Linux" ]; then
  wget https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh -O $HOME/miniconda.sh
fi

bash $HOME/miniconda.sh -b -p $HOME/.dotfiles/conda/.conda
cd $HOME/.dotfiles && stow -R conda
echo export PATH="$HOME/.conda/bin:$PATH" >> $HOME/.extra
rm $HOME/miniconda.sh
source $HOME/.bash_profile

pip install --upgrade pip && conda update conda

conda install jupyter jupyterlab ipykernel \
              numpy pandas pandas-profiling \
              matplotlib seaborn plotly \
              tqdm \
              flask \
              sqlalchemy \
              boto3 \
              sparkmagic -y

if [ "${KERNEL:0:6}" = "Darwin" ]; then
  conda install pyzmq nodejs r-essentials mro-base

  # Renaming Root Python Kernel to differentiate from Environments
  python -m ipykernel install --user --display-name "Python [root]"

  # Create Python 2.7 environment & install Jupyter kernel
  conda env create -f ./init/py27.yml && \
  source activate py27 && \
  python -m ipykernel install --user --name py27 --display-name "Python [py27]" && \
  source deactivate

  # Create Python 3.6 environment & install Jupyter kernel
  conda env create -f ./init/py36.yml && \
  source activate py36 && \
  python -m ipykernel install --user --name py36 --display-name "Python [py36]" && \
  source deactivate

  # # Setup Spark Magic (Spark, PySpark2/3, SparkR)
  # # https://github.com/jupyter-incubator/sparkmagic
  # jupyter nbextension enable --py --sys-prefix widgetsnbextension
  # jupyter-kernelspec install $CONDA_PATH/lib/python3.6/site-packages/sparkmagic/kernels/sparkkernel
  # jupyter-kernelspec install $CONDA_PATH/lib/python3.6/site-packages/sparkmagic/kernels/pysparkkernel
  # jupyter-kernelspec install $CONDA_PATH/lib/python3.6/site-packages/sparkmagic/kernels/pyspark3kernel
  # jupyter-kernelspec install $CONDA_PATH/lib/python3.6/site-packages/sparkmagic/kernels/sparkrkernel
  # jupyter serverextension enable --py sparkmagic
  #
  # # Bash Jupyter Kernel
  # pip install bash_kernel && python -m bash_kernel.install
  #
  # # Install the Javascript kernel for Jupyter
  # # https://github.com/n-riesco/ijavascript
  # npm install -g ijavascript
  # ijsinstall
  #
  # # Setup the R kernel for Jupyter - This should be executed in R.
  # # https://irkernel.github.io/
  # R -e "install.packages(c('repr', 'IRdisplay', 'evaluate', 'crayon', 'pbdZMQ', 'devtools', 'uuid', 'digest'))"
  # R -e "devtools::install_github('IRkernel/IRkernel')"
  # R -e "IRkernel::installspec()"

elif [ "${KERNEL:0:5}" = "Linux" ]; then

  # Mostly taken from [Jose Portilla's Tutorial (https://medium.com/@josemarcialportilla/getting-spark-python-and-jupyter-notebook-running-on-amazon-ec2-dec599e1c297)

  # Setup Jupyter for Remote Access
  jupyter notebook --generate-config

  mkdir $HOME/.jupyter/certs && \
  sudo openssl req -x509 -nodes -days 365 -newkey rsa:1024 -keyout $HOME/.jupyter/certs/jupyter_cert.pem -out $HOME/.jupyter/certs/jupyter_cert.pem

  cd $HOME/.jupyter

  echo "c = get_config()" >> jupyter_notebook_config.py

  # Notebook config this is where you saved your pem cert
  echo c.NotebookApp.certfile = u'$HOME/.certs/jupyter_cert.pem' >> jupyter_notebook_config.py
  # Run on all IP addresses of your instance
  echo c.NotebookApp.ip = '*' >> jupyter_notebook_config.py
  # Don't open browser by default
  echo c.NotebookApp.open_browser = False >> jupyter_notebook_config.py
  # Fix port to 8888
  echo c.NotebookApp.port = 8888 >> jupyter_notebook_config.py


  # Spark Installation
  conda install py4j

  cd $HOME

  wget http://www-us.apache.org/dist/spark/spark-2.3.2/spark-2.3.2-bin-hadoop2.7.tgz && \
  tar xf spark-2.3.2-bin-hadoop2.7.tgz && \
  mv spark-2.3.2-bin-hadoop2.7.tgz .spark && \
  rm spark-2.3.2-bin-hadoop2.7.tgz

  echo export SPARK_PATH="$HOME/.spark" >> $HOME/.extra
  echo export PATH="$PATH:$SPARK_PATH" >> $HOME/.extra
  echo export PYTHONPATH="$SPARK_PATH/python:$PYTHONPATH" >> $HOME/.extra

fi
