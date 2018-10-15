#!/bin/bash

file=~/.tmux.conf

if [ ! -e $file ]; then
    cp -p tmux.conf $file
    cp -Rp tmux ~/.tmux
fi
