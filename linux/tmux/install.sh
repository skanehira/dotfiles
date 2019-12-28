#!/bin/bash

if [[ -v WSL_DISTRO_NAME ]]; then
    ln -s $PWD/tmux_wsl.conf ~/.tmux.conf
else
    ln -s $PWD/tmux_ubuntu.conf ~/.tmux.conf
fi
