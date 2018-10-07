source $HOME/.bash_profile

conda install pyzmq nodejs r-essentials mro-base sparkmagic

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
