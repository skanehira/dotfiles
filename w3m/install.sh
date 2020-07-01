#!/bin/bash
path=~/.w3m

if [ ! -e $path ]; then
    mkdir -p $path
fi

ln -s $PWD/keymap $path/keymap
