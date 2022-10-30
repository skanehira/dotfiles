#!/bin/bash

karabiner_path=$XDG_CONFIG_HOME/karabiner

if [ ! -e "$karabiner_path" ]; then
  mkdir -p "$karabiner_path"
fi

ln -s "$PWD/karabiner.json" "$karabiner_path/karabiner.json"
