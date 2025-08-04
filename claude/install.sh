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

if [[ ! -e $XDG_CONFIG_HOME/claude/hooks ]]; then
  ln -s $PWD/hooks $XDG_CONFIG_HOME/claude/hooks
fi

if [[ ! -e $XDG_CONFIG_HOME/claude/agents ]]; then
  ln -s $PWD/agents $XDG_CONFIG_HOME/claude/agents
fi

if [[ ! -e $XDG_CONFIG_HOME/claude/settings.json ]]; then
  ln -s $PWD/settings.json $XDG_CONFIG_HOME/claude/settings.json
fi
