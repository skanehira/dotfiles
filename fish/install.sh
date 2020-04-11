#!/bin/bash

for f in `ls functions/*.fish`
do
  target=$HOME/.config/fish/functions/${f:10}
  if [[ ! -e $target ]]; then
    ln -s $PWD/$f $target
  fi
done

file=$HOME/.config/fish/config.fish

if [[ ! -e $file ]]; then
  ln -s $PWD/config.fish $file
fi

fish install_fisher.fish
