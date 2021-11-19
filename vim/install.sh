#!/bin/bash
path=~/.vim
nvim_path=~/.config/nvim

if [ ! -e $path ]; then
  mkdir -p $path
fi

if [ ! -e $XDG_CONFIG_HOME/nvim ]; then
  mkdir -p $nvim_path
fi

if [[ ! -e $HOME/.vimrc ]]; then
  ln -s $PWD/vimrc $HOME/.vimrc
fi

if [[ ! -e $path/sonictemplate ]]; then
  ln -s $PWD/sonictemplate $path/sonictemplate
fi

if [[ ! -e $nvim_path/init.vim ]]; then
  ln -s $HOME/.vimrc $nvim_path/init.vim
fi
