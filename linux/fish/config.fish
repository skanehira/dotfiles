set -x GOPATH $HOME/dev/go
set -x GOBIN $GOPATH/bin
set -x PATH $PATH $GOBIN /home/skanehira/.local/bin
set -x FZF_DEFAULT_OPTS "--layout=reverse --inline-info --select-1 --exit-0 -m"
set -x EDITOR vim
set -x LC_CTYPE "en_US.UTF-8"
set -x GHQ_ROOT $GOPATH/src
set -x XDG_CONFIG_HOME $HOME/.config

alias lg="lazygit"
alias buildvim='cd $GOPATH/src/github.com/vim/vim/src && git pull && sudo make distclean && ./configure --enable-gui=gtk3 --enable-fail-if-missing && make && sudo make install'

