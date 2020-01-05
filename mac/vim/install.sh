#!/bin/bash
path=~/.vim

if [ ! -e $path ]; then
	echo "create directory $path"
    mkdir -p $path
fi

ln -s $PWD/dein.toml $path/dein.toml
ln -s $PWD/vimrc ~/.vimrc
