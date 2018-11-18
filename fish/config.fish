# env
set -x GOPATH $HOME/dev/go
set -x GOBIN $GOPATH/bin
set -x PATH $PATH $GOBIN $HOME/.cargo/bin /usr/local/bin
set -x XDG_CONFIG_HOME $HOME/.config
set -x LANG "ja_JP.UTF-8"
set -x HOMEBREW_UPGRADE_CLEANUP 1
set -x FZF_DEFAULT_OPTS "--layout=reverse --inline-info"

# alias
alias lg="lazygit"
alias dry="docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock moncho/dry"
alias ll='ls -lahG'
alias bw='w3m https://google.com'
alias 2gif='docker run --rm -v $PWD:/data asciinema/asciicast2gif'
alias gs='git status'
alias gd='git diff'
alias gl='git log'
alias attach='tmux attach -t (tmux ls | fzf | awk \'{print $1}\' | rev | cut -c 2- | rev)'
