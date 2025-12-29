#!/bin/bash

if [ ! -e $HOME/.claude ]; then
  mkdir -p $HOME/.claude
fi

if [[ ! -e $HOME/.claude/commands ]]; then
  ln -s $PWD/commands $HOME/.claude/commands
fi

if [[ ! -e $HOME/.claude/hooks ]]; then
  ln -s $PWD/hooks $HOME/.claude/hooks
fi

if [[ ! -e $HOME/.claude/agents ]]; then
  ln -s $PWD/agents $HOME/.claude/agents
fi

if [[ ! -e $HOME/.claude/settings.json ]]; then
  ln -s $PWD/settings.json $HOME/.claude/settings.json
fi

if [[ ! -e $HOME/.claude/skills ]]; then
  ln -s $PWD/skills $HOME/.claude/skills
fi

if [[ ! -e $HOME/.claude/rules ]]; then
  ln -s $PWD/rules $HOME/.claude/rules
fi
