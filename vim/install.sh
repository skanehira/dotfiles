#!/bin/bash
path=~/.vim

if [ ! -e $path ]; then
    mkdir -p $path
fi

if [[ ! -e $path/dein.toml ]]; then
    ln -s $PWD/dein.toml $path/dein.toml
fi

if [[ ! -e $HOME/.vimrc ]]; then
    ln -s $PWD/vimrc $HOME/.vimrc
fi

if [[ ! -e $path/sonictemplate ]]; then
    ln -s $PWD/sonictemplate $path/sonictemplate
fi
