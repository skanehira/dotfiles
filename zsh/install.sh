#!/bin/bash

if [[ ! -e $HOME/.zshenv ]]; then
    ln -s $PWD/zshenv $HOME/.zshenv
fi

if [[ ! -e $HOME/.zshrc ]]; then
    ln -s $PWD/zshrc $HOME/.zshrc
fi

if [[ ! -e $HOME/.zprofile ]]; then
    ln -s $PWD/zprofile $HOME/.zprofile
fi
