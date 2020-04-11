#!/bin/bash
if [[ ! -d $HOME/.tmux-themepack ]]; then
    git clone https://github.com/jimeh/tmux-themepack.git ~/.tmux-themepack
fi

if [[ ! -e $HOME/.tmux.conf ]]; then
    ln -s $PWD/tmux.conf ~/.tmux.conf

    case "$(uname)" in
      "Linux" )
        ln -s $PWD/tmux.conf.linux ~/.tmux.conf.linux;;
      "Darwin" )
        ln -s $PWD/tmux.conf.mac ~/.tmux.conf.mac;;
    esac
fi
