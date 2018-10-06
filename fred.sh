KERNEL=$(uname -a)
if [ "${KERNEL:0:6}" = "Darwin" ]; then
  xcode-select --install
	bash brew.sh
  bash conda.sh
  bash atom.sh
elif [ "${KERNEL:0:5}" = "Linux" ]; then
	sudo apt-get update && \
	sudo apt-get upgrade && \
	sudo apt-get install -y stow && \
	# sudo apt-get install -y r-base && \
	# sudo apt-get install -y nodejs && \
	sudo apt install python-pip && \
	bash conda.sh && \
	bash remote.sh;
fi

for folder in ./
	do [[ -f $folder ]] && stow $folder
  do [[ -d $folder ]] && stow $folder
done
