#!/bin/bash
vim_files=`ls -ld ~/.vim/*.toml | awk '{print $9}'`
tmux_file=~/.tmux.conf
fish_functions='c.fish cm.fish cs.fish fd.fish fssh.fish ftmux.fish push.fish rec.fish fvim.fish'

# update nvim files
cp -p $vim_files vim/
cp -p ~/.vimrc vim/vimrc

# update tmux file
cp -p $tmux_file tmux/tmux.conf
cp -rp ~/.tmux/ tmux/tmux/

# update fish
cp -p ~/.config/fish/config.fish fish/

for f in $fish_functions
do
    cp -p ~/.config/fish/functions/$f fish/functions/
done
