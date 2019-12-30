#!/bin/bash
file=tmux_ubuntu.conf

if [[ -v WSL_DISTRO_NAME ]]; then
    file=tmux_wsl.conf
fi

if [[ ! -d $HOME/.tmux-themepack ]]; then
    git clone https://github.com/jimeh/tmux-themepack.git ~/.tmux-themepack
fi

if [[ ! -e $HOME/.tmux.conf ]]; then
    ln -s $PWD/$file ~/.tmux.conf
fi
