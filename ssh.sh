ssh-keygen -f $HOME/.ssh/id_rsa -t rsa -b 4096 -C "fred@fredabood.com";

echo "
Host github.com
  HostName github.com
  User git
  IdentityFile $HOME/.ssh/id_rsa

Host gitlab.com
  HostName gitlab.com
  User git
  PubkeyAuthentication yes
  IdentityFile $HOME/.ssh/id_rsa

Host nu.bootcampcontent.com
  HostName nu.bootcampcontent.com
  User git
  IdentityFile $HOME/.ssh/id_rsa
" >> ~/.ssh/config
