#!/bin/bash
# version 0.0.1 2018/12/28
cat <<EOS
###############################################################
# pre settings
###############################################################
EOS
echo "# mkdir GOPATH and GOBIN dir"
mkdir -p ~/dev/go/src/github.com/skanehira
mkdir -p ~/dev/go/bin

echo "# mkdir vim plugin dir ~/.cache/dein"
mkdir -p ~/.cache/dein

echo "# mkdir ~/.tmux"
mkdir -p ~/.tmux

echo "# install xcode"
open "https://itunes.apple.com/jp/app/xcode/id497799835?mt=12&ign-mpt=uo%3D4"
read -p "continue?"

echo "# install xcode tool"
xcode-select --install
read -p "continue?"

cat <<EOS
###############################################################
# brew
###############################################################
EOS
echo "# install"
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"

echo "# update"
brew update

echo "# brew doctor"
brew doctor

read -p "continue?"

cat <<EOS
###############################################################
# fzf
###############################################################
EOS
echo "# install"
brew install fzf

cat <<EOS
###############################################################
# git
###############################################################
EOS
echo "# install"
brew install git

echo "# config user.name user.email merge.tool"
git config --global user.name "skanehira"
git config --global user.email sho19921005@gmail.com
git config --global merge.tool vimdiff

cat <<EOS
###############################################################
# dotfiles
###############################################################
EOS
echo "# get dotfiles"
git clone git@github.com:skanehira/dotfiles.git ~/dev/go/src/github.com/skanehira/dotfiles

dotfiles=~/dev/go/src/github.com/skanehira/dotfiles/mac

echo "# setup bashrc"
cd $dotfiles/bash
bash install.sh
source ~/.bashrc

cat <<EOS
###############################################################
# git
###############################################################
EOS
echo "# install python3"
brew install python3

cat <<EOS
###############################################################
# Node.js
###############################################################
EOS
echo "# install nodebrew"
brew install node

cat <<EOS
###############################################################
# tmux
###############################################################
EOS
echo "# install tmux"
brew install tmux

echo "# setup"
cd $dotfiles/tmux
bash install.sh

cat <<EOS
###############################################################
# fish
###############################################################
EOS
echo "# install fish"
brew install fish

echo "# install powerline"
pip3 install --user git+git://github.com/powerline/powerline

echo "# install powerline font"
git clone https://github.com/powerline/fonts.git --depth=1
cd fonts
./install.sh
cd ..
rm -rf fonts

echo "# install fisher"
curl https://git.io/fisher --create-dirs -sLo ~/.config/fish/functions/fisher.fish

echo "# install bobthefish, z"
fish -C 'fisher add oh-my-fish/theme-bobthefish;and fisher add fisher add jethrokuan/z'

echo "# setup"
cd $dotfiles/fish
bash install.sh

cat <<EOS
###############################################################
# asciinema
###############################################################
EOS
echo "# install"
brew install asciinema

echo "# config"
asciinema auth

read -p "continue?"

cat <<EOS
###############################################################
# Alacritty
###############################################################
EOS
echo "# install"
brew cask install alacritty

echo "# setup"
cd $dotfiles/alacritty
bash install.sh

cat <<EOS
###############################################################
# Go
###############################################################
EOS
echo "# install"
brew install go

cat <<EOS
###############################################################
# vim
###############################################################
EOS
echo "# install"
brew install vim

echo "# setup"
cd $dotfiles/vim
bash install.sh

echo "# run vim"
vim
