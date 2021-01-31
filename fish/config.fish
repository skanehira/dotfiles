# env
set -x GOPATH $HOME/dev/go
set -x GOBIN $GOPATH/bin
set -x PATH $PATH $GOBIN /usr/local/go/bin
set -x XDG_CONFIG_HOME $HOME/.config
set -x LANG en_US.utf8
set -x HOMEBREW_INSTALL_CLEANUP 1
set -x FZF_DEFAULT_OPTS "--layout=reverse --inline-info --exit-0 -m"
set -x FZF_DEFAULT_COMMAND "ag -g ."
set -g theme_display_date no
set -x TERM screen-256color
set -x LSCOLORS gxfxcxdxbxegedabagacad
set -x EDITOR vim
set -x LC_CTYPE "en_US.UTF-8"
set -x GHQ_ROOT $GOPATH/src
set -x GO111MODULE auto
set -x GOENV_ROOT $HOME/.goenv
set -x PATH "$GOENV_ROOT/bin:$PATH"
set -x DENO_INSTALL "/home/skanehira/.deno"
set -x PATH "$DENO_INSTALL/bin:$PATH"
set -x GOENV_DISABLE_GOPATH 1

# alias
alias lg="lazygit"
alias ll='ls -lahG'
alias g='git'
alias gs='git status'
alias gpl='git pull'
alias gp='git push'
alias ga='git add .'
alias gm='git commit -a'
alias gma='git commit --amend'
alias glo='git log --oneline'
alias gd='git diff'
alias gl='git log'
alias gdc='git diff (git log --pretty=oneline | fzf | awk "{print \$1}")'
alias www="w3m google.com"

switch (uname)
  case Linux
    alias buildvim='cd $GOPATH/src/github.com/vim/vim/src && git pull && sudo make distclean && ./configure --with-x --enable-multibyte --enable-fail-if-missing && make && sudo make install && cd -'
    alias open="xdg-open"
  case Darwin
    alias buildvim='cd $GOPATH/src/github.com/vim/vim/src && git pull && sudo make distclean && ./configure --enable-fail-if-missing && make && sudo make install && cd -'
end

# use vi mode in fish
fish_vi_key_bindings

goenv init - | source
