KERNEL=$(uname -a)

if [ ! -d $HOME/.conda ]; then

  if [ "${KERNEL:0:6}" = "Darwin" ]; then
    wget https://repo.continuum.io/miniconda/Miniconda3-latest-MacOSX-x86_64.sh -O $HOME/miniconda.sh
  elif [ "${KERNEL:0:5}" = "Linux" ]; then
    wget https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh -O $HOME/miniconda.sh
  fi

  bash $HOME/miniconda.sh -b -p $HOME/.conda && rm $HOME/miniconda.sh && source $HOME/.bash_profile
  # cd $HOME/.dotfiles && stow -R data

  # Installing all packages at once causes a memory overload on a micro EC2 instance
  pip install --upgrade pip && conda update conda -y
  conda install jupyter jupyterlab ipykernel -y
  conda install numpy pandas pandas-profiling -y
  conda install matplotlib seaborn plotly -y
  conda install tqdm flask sqlalchemy boto3 -y

else
  pip install --upgrade pip && conda update conda -y && conda update --all

fi

if [ "${KERNEL:0:6}" = "Darwin" ]; then

  conda install pyzmq nodejs r-essentials mro-base sparkmagic -y

  # Renaming Root Python Kernel to differentiate from Environments
  python -m ipykernel install --user --display-name "Python [root]"

  if [ ! -d $HOME/.conda/envs/py27 ]; then
    conda env create -f $HOME/init/py27.yml
    source activate py27
    python -m ipykernel install --user --name py27 --display-name "Python [py27]"
    source deactivate
  fi

  if [ ! -d $HOME/.conda/envs/py36 ]; then
    # Create Python 3.6 environment & install Jupyter kernel
    conda env create -f $HOME/init/py36.yml
    source activate py36
    python -m ipykernel install --user --name py36 --display-name "Python [py36]"
    source deactivate
  fi

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

  # Mostly taken from Jose Portilla's Tutorial (https://medium.com/@josemarcialportilla/getting-spark-python-and-jupyter-notebook-running-on-amazon-ec2-dec599e1c297)

  if [ ! -d $HOME/.jupyter ]; then
    # Setup Jupyter for Remote Access
    jupyter notebook --generate-config

    mkdir $HOME/.jupyter/certs
    sudo openssl req -x509 -nodes -days 365 -newkey rsa:1024 -keyout $HOME/.jupyter/certs/jupyter_cert.pem -out $HOME/.jupyter/certs/jupyter_cert.pem

    echo "c = get_config()" >> $HOME/.jupyter/jupyter_notebook_config.py

    # Notebook config this is where you saved your pem cert
    echo c.NotebookApp.certfile = u'$HOME/.certs/jupyter_cert.pem' >> $HOME/.jupyter/jupyter_notebook_config.py
    # Run on all IP addresses of your instance
    echo c.NotebookApp.ip = '*' >> $HOME/.jupyter/jupyter_notebook_config.py
    # Don't open browser by default
    echo c.NotebookApp.open_browser = False >> $HOME/.jupyter/jupyter_notebook_config.py
    # Fix port to 8888
    echo c.NotebookApp.port = 8888 >> $HOME/.jupyter/jupyter_notebook_config.py
  fi

  if [ ! -d $HOME/.spark ]; then
    sudo apt-get install default-jre -y
    sudo apt-get install scala -y
    conda install py4j -y

    # Spark Installation
    wget http://www-us.apache.org/dist/spark/spark-2.3.2/spark-2.3.2-bin-hadoop2.7.tgz
    tar xf spark-2.3.2-bin-hadoop2.7.tgz && rm spark-2.3.2-bin-hadoop2.7.tgz

    mv spark-2.3.2-bin-hadoop2.7 $HOME/.spark
    source $HOME/.bash_profile
    # cd $HOME/.dotfiles && stow -R data
  fi

fi
