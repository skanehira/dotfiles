#!/bin/bash
path=$XDG_CONFIG_HOME/yazi

if [ ! -e "$path" ]; then
  mkdir -p "$path"
fi

if [[ ! -e $XDG_CONFIG_HOME/yazi/yazi.toml ]]; then
  ln -s "$PWD/yazi.toml" "$XDG_CONFIG_HOME/yazi/yazi.toml"
fi
