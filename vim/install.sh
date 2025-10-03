#!/bin/bash
path=~/.vim
nvim_path=$XDG_CONFIG_HOME/nvim

if [ ! -e $path ]; then
  mkdir -p $path
fi

if [ ! -e $XDG_CONFIG_HOME/nvim ]; then
  mkdir -p $nvim_path
fi

if [[ ! -e $HOME/.vimrc ]]; then
  ln -s $PWD/vimrc $HOME/.vimrc
fi

if [[ ! -e $nvim_path/init.lua ]]; then
  ln -s $PWD/init.lua $nvim_path/init.lua
fi

if [[ ! -e $nvim_path/lua ]]; then
  ln -s $PWD/lua $nvim_path/lua
fi

if [[ ! -e $nvim_path/after ]]; then
  ln -s $PWD/after $nvim_path/after
fi
