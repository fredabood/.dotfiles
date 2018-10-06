sudo apt-get install default-jre && \
sudo apt-get install scala && \
conda install py4j;

################################################################################
# JUPYTER SETUP
################################################################################

jupyter notebook --generate-config;

mkdir $HOME/.jupyter/certs && \
sudo openssl req -x509 -nodes -days 365 -newkey rsa:1024 -keyout $HOME/.jupyter/certs/jupyter_cert.pem -out $HOME/.jupyter/certs/jupyter_cert.pem;

echo c = get_config() >> $HOME/.jupyter/jupyter_notebook_config.py;

# Notebook config this is where you saved your pem cert
echo c.NotebookApp.certfile = u'$HOME/.certs/jupyter_cert.pem' >> $HOME/.jupyter/jupyter_notebook_config.py;
# Run on all IP addresses of your instance
echo c.NotebookApp.ip = '*' >> $HOME/.jupyter/jupyter_notebook_config.py;
# Don't open browser by default
echo c.NotebookApp.open_browser = False >> $HOME/.jupyter/jupyter_notebook_config.py;
# Fix port to 8888
echo c.NotebookApp.port = 8888 >> $HOME/.jupyter/jupyter_notebook_config.py;


################################################################################
# SPARK SETUP
################################################################################

wget http://www-us.apache.org/dist/spark/spark-2.3.2/spark-2.3.2-bin-hadoop2.7.tgz;

tar xf spark-2.3.2-bin-hadoop2.7.tgz && \
mv spark-2.3.2-bin-hadoop2.7.tgz .spark && \
rm spark-2.3.2-bin-hadoop2.7.tgz;

echo export SPARK_PATH="$HOME/.spark" >> $HOME/.extra;
echo export PATH="$PATH:$SPARK_PATH" >> $HOME/.extra;
echo export PYTHONPATH="$SPARK_PATH/python:$PYTHONPATH" >> $HOME/.extra;
