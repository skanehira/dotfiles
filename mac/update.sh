#!/bin/bash
vim_files=`ls -ld ~/.vim/*.toml | awk '{print $9}'`
tmux_file=~/.tmux.conf

# update vim files
cp -p $vim_files vim/
cp -p ~/.vimrc vim/vimrc
cp -p ~/.vim/UltiSnips/go.snippets vim/go/go.snippets

# update tmux file
cp -p $tmux_file tmux/tmux.conf
cp -rp ~/.tmux/ tmux/tmux/

# update fish
cp -p ~/.config/fish/config.fish fish/
cp -p ~/.config/fish/functions/* fish/functions/

# update bashrc
cp -p ~/.bashrc ./bash/bashrc

# update alacritty
cp -p ~/.config/alacritty/alacritty.yml ./alacritty/alacritty.yml
