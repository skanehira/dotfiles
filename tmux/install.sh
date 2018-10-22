#!/bin/bash

file=~/.tmux.conf

cp -p tmux.conf $file
cp -Rp tmux/* ~/.tmux/
