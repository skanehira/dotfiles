#!/bin/bash
path=~/.vim

if [ ! -e $path ]; then
    mkdir -p $path
fi

if [[ ! -e $HOME/.vimrc ]]; then
    ln -s $PWD/vimrc $HOME/.vimrc
fi

if [[ ! -e $HOME/.plugin.vim ]]; then
    ln -s $PWD/plugin.vim $HOME/.plugin.vim
fi

if [[ ! -e $path/sonictemplate ]]; then
    ln -s $PWD/sonictemplate $path/sonictemplate
fi
