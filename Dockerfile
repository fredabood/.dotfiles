FROM ubuntu

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
ENV PATH /opt/conda/bin:$PATH

RUN apt-get update --fix-missing \
 && apt-get install -y \
    bzip2 \
    ca-certificates \
    curl \
    git \
    python-pip \
    stow \
    screen \
    vim \
    wget \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Setup File System
RUN git clone https://github.com/fredabood/.dotfiles.git /root/.dotfiles \
 && /bin/bash /root/.dotfiles/bootstrap.sh -f \
 && /bin/bash -c "source /root/.bash_profile"

# Install Miniconda3
RUN wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-4.5.11-Linux-x86_64.sh -O ~/miniconda.sh \
 && /bin/bash ~/miniconda.sh -b -p /opt/conda \
 && rm ~/miniconda.sh \
 && /opt/conda/bin/conda clean -tipsy \
 && ln -s /opt/conda/etc/profile.d/conda.sh /etc/profile.d/conda.sh \
 && echo ". /opt/conda/etc/profile.d/conda.sh" >> /root/.dotfiles/home/.bash_profile \
 && echo "conda activate base" >> /root/.dotfiles/home/.bash_profile

ENV TINI_VERSION v0.16.1
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /usr/bin/tini
RUN chmod +x /usr/bin/tini

# Open Ports for Jupyter
EXPOSE 8888

#Setup File System
RUN mkdir /root/projects
ENV SHELL=/bin/bash
VOLUME /root/projects
WORKDIR /root/projects

ENTRYPOINT [ "/usr/bin/tini", "--" ]
CMD [ "/bin/bash" ]
