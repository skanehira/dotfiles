#!/bin/bash
# version 0.0.1 2018/12/05

cat <<EOS
###############################################################
# install git
###############################################################
EOS
yum -y install git

cat <<EOS
###############################################################
# install golang
###############################################################
EOS
sudo curl https://dl.google.com/go/go1.11.2.linux-amd64.tar.gz -o /usr/local/src/go.tar.gz
sudo tar -C /usr/local -xzf /usr/local/src/go.tar.gz

tee -a ~/.bashrc <<'EOS'
export GOROOT=/usr/local/go
export GOPATH=~/go
export GOBIN=$GOPATH/bin
export PATH=$PATH:$GOBIN:$GOROOT/bin
EOS

source ~/.bashrc

cat <<EOS
###############################################################
# instal fzf
###############################################################
EOS
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install

cat <<EOS
###############################################################
# instal tmux
###############################################################
EOS
sudo yum -y install gcc libevent-devel ncurses-devel
sudo curl https://github.com/tmux/tmux/releases/download/2.8/tmux-2.8.tar.gz -Lo /usr/local/src/tmux.tar.gz
sudo tar -C /usr/local/src -xzf /usr/local/src/tmux.tar.gz
cd /usr/local/src/tmux-2.8
sudo ./configure --prefix=/usr/local/tmux
sudo make
sudo make install

echo 'export PATH=$PATH:/usr/local/tmux/bin' >> ~/.bashrc
source ~/.bashrc

cat <<EOS
###############################################################
# instal fish shell
###############################################################
EOS

cd /etc/yum.repos.d/
sudo wget https://download.opensuse.org/repositories/shells:fish:release:2/CentOS_7/shells:fish:release:2.repo
sudo yum -y install fish

cat <<EOS
###############################################################
# instal fish plugin manager fisherman
###############################################################
EOS

curl https://git.io/fisher --create-dirs -sLo ~/.config/fish/functions/fisher.fish
fish -C 'fisher add oh-my-fish/theme-bobthefish;and fisher add fisher add jethrokuan/z'

cat <<EOS
###############################################################
# instal docker
###############################################################
EOS

sudo curl -fsSL get.docker.com -o get-docker.sh
sudo sh get-docker.sh

systemctl start docker
systemctl enable docker
sudo usermod -aG docker `whoami`

