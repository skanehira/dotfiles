#!/bin/bash
cp ../../fish/functions/* ~/.config/fish/functions

file=$HOME/.config/fish/config.fish
if [[ ! -e $file ]]; then
    ln -s $PWD/config.fish $file
fi

fish install_fisher.fish
