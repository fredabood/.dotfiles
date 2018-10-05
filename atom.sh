wget https://atom.io/download/mac && \
unzip $HOME/Downloads/atom-mac.zip && \
mv $HOME/Downloads/atom-mac/Atom.app /Applications/Atom.app;

apm install atom-ide-ui \
            ide-python ide-r ide-typescript \
            hydrogen hydrogen-launcher \
            git-plus git-time-machine split-diff \
            platformio-ide-terminal \
            highlight-line \
            tablr \
            pretty-json;
