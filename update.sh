#!/bin/bash
nvim_files=`ls -ld ~/.config/nvim/* | awk '{print $9}'`
tmux_file=~/.tmux.conf
fish_functions='c.fish cm.fish cs.fish fd.fish fssh.fish ftmux.fish push.fish rec.fish vim.fish'

# update nvim files
cp -p $nvim_files nvim/

# update tmux file
cp -p $tmux_file tmux/tmux.conf

# update fish
cp -p ~/.config/fish/config.fish fish/

for f in $fish_functions
do
    cp -p ~/.config/fish/functions/$f fish/functions/
done
