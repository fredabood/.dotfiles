KERNEL=$(uname -a)
if [ "${KERNEL:0:6}" = "Darwin" ]; then
  wget https://repo.continuum.io/miniconda/Miniconda3-latest-MacOSX-x86_64.sh -O $HOME/miniconda.sh;
elif [ "${KERNEL:0:5}" = "Linux" ]; then
  wget https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh -O $HOME/miniconda.sh;
fi

bash $HOME/miniconda.sh -b -p $HOME/.conda && \
echo export PATH="$HOME/.conda/bin:$PATH" >> $HOME/.extra && \
rm $HOME/miniconda.sh && \
source $HOME/.dotfiles/.bash_profile

pip install --upgrade pip && conda update conda

conda install jupyter jupyterlab ipykernel \
							numpy pandas pandas-profiling \
							matplotlib seaborn plotly \
              tqdm \
							flask \
							sqlalchemy \
							boto3 \
              pyzmq nodejs \
              sparkmagic \
              r-essentials mro-base \
              argcomplete -y

eval "$(register-python-argcomplete conda)"

pip install bash_kernel && python -m bash_kernel.install
python -m ipykernel install --user --display-name "Python [root]"

conda env create -f ./init/py27.yml && \
source activate py27 && \
python -m ipykernel install --user --name py27 --display-name "Python [py27]" && \
source deactivate

conda env create -f ./init/py36.yml && \
source activate py36 && \
python -m ipykernel install --user --name py36 --display-name "Python [py36]" && \
source deactivate

# # Install the Javascript kernel for Jupyter
# # https://github.com/n-riesco/ijavascript
# npm install -g ijavascript
# ijsinstall
#
# # Setup the R kernel for Jupyter - This should be executed in R.
# # https://irkernel.github.io/
# sudo R -e "install.packages(c('repr', 'IRdisplay', 'evaluate', 'crayon', 'pbdZMQ', 'devtools', 'uuid', 'digest'))"
# sudo R -e "devtools::install_github('IRkernel/IRkernel')"
# sudo R -e "IRkernel::installspec()"

# Setup Spark Magic (Spark, PySpark2/3, SparkR)
# https://github.com/jupyter-incubator/sparkmagic
jupyter nbextension enable --py --sys-prefix widgetsnbextension
jupyter-kernelspec install $CONDA_PATH/lib/python3.6/site-packages/sparkmagic/kernels/sparkkernel
jupyter-kernelspec install $CONDA_PATH/lib/python3.6/site-packages/sparkmagic/kernels/pysparkkernel
jupyter-kernelspec install $CONDA_PATH/lib/python3.6/site-packages/sparkmagic/kernels/pyspark3kernel
jupyter-kernelspec install $CONDA_PATH/lib/python3.6/site-packages/sparkmagic/kernels/sparkrkernel
jupyter serverextension enable --py sparkmagic
