#!/bin/bash

dest=$HOME/.gitconfig

if [ ! -e $dest ]; then
  ln -s "$PWD/.gitconfig" $dest
fi
