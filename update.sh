#!/bin/bash
nvim_files=`ls -ld ~/.config/nvim/* | awk '{print $9}'`
tmux_file=~/.tmux.conf

# update nvim files
cp -p $nvim_files nvim/

# update tmux file
cp -p $tmux_file tmux/tmux.conf

# update fish
cp -p ~/.config/fish/config.fish fish/
cp -Rp ~/.config/fish/functions fish/
