set -x GOPATH $HOME/dev/go
set -x GOBIN $GOPATH/bin
set -x THEMIS_HOME $HOME/.cache/dein/repos/github.com/thinca/vim-themis
set -x PATH $PATH $GOBIN $THEMIS_HOME/bin
set -x FZF_DEFAULT_OPTS "--layout=reverse --inline-info --select-1 --exit-0 -m --bind ctrl-a:toggle-all"
set -x FZF_DEFAULT_COMMAND 'ag --nocolor -g .'
set -x EDITOR vim
set -x LC_CTYPE "en_US.UTF-8"
set -x GHQ_ROOT $GOPATH/src
set -x XDG_CONFIG_HOME $HOME/.config
set -x LANG "en_US.UTF8"
set -x GO111MODULE auto

alias gs="git status"
alias lg="lazygit"
alias buildvim='cd $GOPATH/src/github.com/vim/vim/src && git pull && sudo make distclean && ./configure --with-x --enable-multibyte --enable-fail-if-missing && make && sudo make install && cd -'
alias open="xdg-open"
alias gl="git log"

# use vi mode in fish
fish_vi_key_bindings

functions --copy cd standard_cd

function cd
  standard_cd $argv; and ls
end
