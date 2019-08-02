# env
set -x GOPATH $HOME/dev/go
set -x GOBIN $GOPATH/bin
set -x PATH $PATH $GOBIN $HOME/.cargo/bin /usr/local/bin $HOME/.config/composer/vendor/bin
set -x XDG_CONFIG_HOME $HOME/.config
set -x PATH "/usr/local/opt/llvm/bin" $PATH
set -x LANG "ja_JP.UTF-8"
set -x HOMEBREW_INSTALL_CLEANUP 1
set -x FZF_DEFAULT_OPTS "--layout=reverse --inline-info --select-1 --exit-0 -m"
set -g theme_display_date no
set -x TERM xterm-256color
set -x LSCOLORS gxfxcxdxbxegedabagacad
set -x GO111MODULE on
set -x EDITOR vim
set -x LC_CTYPE "en_US.UTF-8"

# alias
alias lg="lazygit"
alias dry="docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock moncho/dry"
alias ll='ls -lahG'
alias bw='w3m https://google.com'
alias 2gif='docker run --rm -v $PWD:/data asciinema/asciicast2gif'
alias gs='git status'
alias gd='git diff'
alias gl='git log'
alias gc='git checkout .'
alias gf='gol -f'
alias repo='cd ( ls -ld $GOPATH/src/*/*/* | awk \'{print $9}\' | fzf )'
alias buildvim='cd /Users/skanehira/dev/go/src/github.com/skanehira/vim/src && sudo make distclean && ./configure --enable-python3interp=yes --enable-fail-if-missing && make && sudo make install'
alias vimt='vim -c ":bo term ++rows=20"'
