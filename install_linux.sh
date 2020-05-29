#!/bin/bash

echo Install Docker
VERSION=$(lsb_release -d | awk '{print $3}')

if [ "$VERSION" == "20.04" ]; then
  # https://linuxconfig.org/how-to-install-docker-on-ubuntu-20-04-lts-focal-fossa
  sudo apt install docker.io
  sudo systemctl enable --now docker
  sudo usermod -aG docker skanehira
else
  curl https://get.docker.com | sh
fi

echo Install fish
sudo apt-add-repository ppa:fish-shell/release-3
sudo apt-get update
sudo apt-get install fish

echo Install Go
curl -L https://dl.google.com/go/go1.14.2.linux-amd64.tar.gz -o go.tar.gz
sudo tar -C /usr/local -xzf go.tar.gz
rm -rf go.tar.gz

mkdir -p ~/dev/go
echo "export PATH=\$PATH:/usr/local/go/bin" >> ~/.bash_profile
echo "export GOPATH=~/dev/go" >> ~/.bash_profile
echo "export GOBIN=\$GOPATH/bin" >> ~/.bash_profile
echo "export PATH=\$PATH:\$GOBIN" >> ~/.bash_profile
source  ~/.bash_profile

echo Install ghq
go get github.com/x-motemen/ghq

echo "export GHQ_ROOT=\$GOPATH/src" >> ~/.bash_profile
source  ~/.bash_profile

echo Install tmux
sudo apt install git automake bison build-essential pkg-config libevent-dev libncurses5-dev
ghq get https://github.com/tmux/tmux
cd $GOPATH/src/github.com/tmux/tmux
./autogen.sh
./configure --prefix=/usr/local
make
sudo make install

echo Setup tmux
cd ../tmux && bash install.sh

echo Install fzf
ghq get https://github.com/junegunn/fzf
cd $GOPATH/src/github.com/junegunn/fzf
go install

echo Install ag
sudo apt-get install silversearcher-ag

echo Clone my dotfiles
ghq get github.com/skanehira/dotfiles
cd $GOPATH/src/github.com/skanehira/dotfiles

echo Setup fish
mkdir ~/.config/fish/functions
cd fish && bash install.sh

echo Uninstall exist vim
sudo apt remove vim
sudo apt autoremove vim

echo Install libxmu-dev to build vim --with-x
sudo apt -y install libxmu-dev

echo Install vim
ghq get https://github.com/vim/vim
cd $GOPATH/src/github.com/vim/vim
./configure --with-x --enable-multibyte --enable-fail-if-missing && make && sudo make install && cd -

echo Setup vim
cd $GOPATH/src/github.com/skanehira/dotfiles/vim
bash install.sh
