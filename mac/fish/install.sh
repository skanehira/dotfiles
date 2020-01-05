#!/bin/bash
cp functions/* ~/.config/fish/functions

file=$HOME/.conf/fish/config.fish
if [[ ! -e $file ]]; then
    ln -s $PWD/config.fish $file
fi
