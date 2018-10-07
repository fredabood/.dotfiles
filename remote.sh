source $HOME/.bash_profile

# Mostly taken from [Jose Portilla's Tutorial (https://medium.com/@josemarcialportilla/getting-spark-python-and-jupyter-notebook-running-on-amazon-ec2-dec599e1c297)

sudo apt-get install default-jre && \
sudo apt-get install scala && \
conda install py4j

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

# Spark Installation
wget http://www-us.apache.org/dist/spark/spark-2.3.2/spark-2.3.2-bin-hadoop2.7.tgz
tar xf spark-2.3.2-bin-hadoop2.7.tgz && rm spark-2.3.2-bin-hadoop2.7.tgz

mv spark-2.3.2-bin-hadoop2.7 $HOME/.dotfiles/data/.spark

echo export PATH="$PATH:$HOME/.spark/bin" >> $HOME/.extra
cd $HOME/.dotfiles && stow -R data
# echo export PYTHONPATH="$HOME/.dotfiles/data/.spark/python:$PYTHONPATH" >> $HOME/.extra
