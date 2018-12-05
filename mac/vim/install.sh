#!/bin/bash
path=~/.vim

if [ ! -e $path ]; then
	echo "create directory $path"
    mkdir -p $path
fi

cp -p *.toml $path/
cp -p vimrc ~/.vimrc
cp -p go/go.snippets ~/.cache/dein/repos/github.com/fatih/vim-go/gosnippets/UltiSnips/go.snippets
