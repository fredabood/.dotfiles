FROM ubuntu

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
ENV PATH /opt/conda/bin:$PATH

RUN apt-get update --fix-missing && \
    apt-get install -y wget bzip2 ca-certificates curl git stow vim screen python-pip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

#Setup File System
RUN git clone https://github.com/fredabood/.dotfiles.git $HOME/.dotfiles && \
    /bin/bash $HOME/.dotfiles/bootstrap.sh -f && \
    /bin/bash -c "source $HOME/.bash_profile"

RUN wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-4.5.11-Linux-x86_64.sh -O ~/miniconda.sh && \
    /bin/bash ~/miniconda.sh -b -p /opt/conda && \
    rm ~/miniconda.sh && \
    /opt/conda/bin/conda clean -tipsy && \
    ln -s /opt/conda/etc/profile.d/conda.sh /etc/profile.d/conda.sh && \
    echo ". /opt/conda/etc/profile.d/conda.sh" >> $HOME/.dotfiles/home/.bash_profile && \
    echo "conda activate base" >> $HOME/.dotfiles/home/.bash_profile

ENV TINI_VERSION v0.16.1
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /usr/bin/tini
RUN chmod +x /usr/bin/tini

# Open Ports for Jupyter
EXPOSE 8888

#Setup File System
RUN mkdir $HOME/projects
ENV SHELL=/bin/bash
VOLUME $HOME/projects
WORKDIR $HOME/projects

ENTRYPOINT [ "/usr/bin/tini", "--" ]
CMD [ "/bin/bash" ]
