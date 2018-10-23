FROM ubuntu:latest

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
ENV PATH /opt/conda/bin:$PATH

RUN apt-get update --fix-missing && \
    apt-get install -y wget bzip2 ca-certificates curl git && \
    apt-get clean && \
    apt get install stow && \
    rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/fredabood/.dotfiles.git ~/.dotfiles && \
    rm ~/.dotfiles/home/.path && \
    bash ~/.dotfiles/bootstrap.sh && \
    source ~/.bash_profile

RUN wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/conda.sh && \
    /bin/bash ~/conda.sh -b -p /opt/conda && \
    rm ~/conda.sh && \
    /opt/conda/bin/conda clean -tipsy && \
    ln -s /opt/conda/etc/profile.d/conda.sh /etc/profile.d/conda.sh && \
    echo ". /opt/conda/etc/profile.d/conda.sh" >> ~/.dotfiles/home/.bash_profile && \
    echo "conda activate base" >> ~/.dotfiles/home/.bash_profile

ENV TINI_VERSION v0.16.1
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /usr/bin/tini
RUN chmod +x /usr/bin/tini

ENTRYPOINT [ "/usr/bin/tini", "--" ]
CMD [ "/bin/bash" ]
