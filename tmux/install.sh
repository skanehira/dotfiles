#!/bin/bash

file=~/.tmux.conf

if [ ! -e $file ]; then
    cp -p tmux.conf $file
fi

cp -Rp tmux ~/.tmux
