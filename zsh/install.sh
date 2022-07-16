#!/bin/bash

if [[ ! -e $HOME/.zshrc ]]; then
    ln -s $PWD/zshrc $HOME/.zshrc
fi

if [[ ! -e $HOME/.zprofile ]]; then
    ln -s $PWD/zprofile $HOME/.zprofile
fi
