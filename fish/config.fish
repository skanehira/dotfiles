# env
set -x GOPATH $HOME/dev/go
set -x GOBIN $GOPATH/bin
set -x PATH $PATH $GOBIN $HOME/.cargo/bin /usr/local/bin
set -x XDG_CONFIG_HOME $HOME/.config

# alias
alias lg="lazygit"
alias dry="docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock moncho/dry"
alias ll='ls -lahG'
alias bw='w3m https://google.com'
alias 2gif='docker run --rm -v $PWD:/data asciinema/asciicast2gif'
alias gs='git status'
alias gd='git diff'
alias gl='git log'
