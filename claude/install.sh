#!/bin/bash

if [ ! -e $XDG_CONFIG_HOME/claude ]; then
  mkdir -p $XDG_CONFIG_HOME/claude
fi

if [[ ! -e $XDG_CONFIG_HOME/claude/CLAUDE.md ]]; then
  ln -s $PWD/CLAUDE.md $XDG_CONFIG_HOME/claude/CLAUDE.md
fi

if [[ ! -e $XDG_CONFIG_HOME/claude/commands ]]; then
  ln -s $PWD/commands $XDG_CONFIG_HOME/claude/commands
fi
