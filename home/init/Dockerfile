# reference: https://hub.docker.com/_/ubuntu/
FROM ubuntu

##Set environment variables
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

RUN sudo apt-get update && upgrade && \
    sudo apt-get install stow python-pip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN echo 'export PATH=/opt/.conda/bin:$PATH' > /etc/profile.d/conda.sh && \
    wget --quiet https://repo.continuum.io/miniconda/Miniconda3-latest-MacOSX-x86_64.sh -O $HOME/miniconda.sh && \
    /bin/bash ~/miniconda.sh -b -p /opt/.conda && \
    rm ~/miniconda.sh

ENV PATH /opt/.conda/bin:$PATH

RUN pip install --upgrade pip && conda update conda -y
RUN conda install jupyter jupyterlab ipykernel \
                  numpy pandas pandas-profiling \
                  matplotlib seaborn plotly \
                  tqdm flask sqlalchemy boto3 \
                  py4j cython pyspark -y

# Open Ports for Jupyter
EXPOSE 7745

#Setup File System
RUN mkdir ds
ENV HOME=/ds
ENV SHELL=/bin/bash
VOLUME /ds
WORKDIR /ds

# Run the shell
CMD  ["/bin/bash"]
