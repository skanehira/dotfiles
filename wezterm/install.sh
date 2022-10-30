#!/bin/bash

wezterm_path=$XDG_CONFIG_HOME/wezterm

if [ ! -e "$wezterm_path" ]; then
  mkdir -p "$wezterm_path"
fi

ln -s "$PWD/wezterm.lua" "$wezterm_path/wezterm.lua"
