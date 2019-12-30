#!/bin/bash
if [[ ! -d $HOME/.tmux-themepack ]]; then
    git clone https://github.com/jimeh/tmux-themepack.git ~/.tmux-themepack
fi

if [[ ! -e $HOME/.tmux.conf ]]; then
    ln -s $PWD/tmux.conf ~/.tmux.conf
fi
