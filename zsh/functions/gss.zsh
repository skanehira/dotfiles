gss() {
  local in_zle=0 saved_buffer saved_cursor
  if [[ -n $WIDGET ]]; then
    in_zle=1
    saved_buffer=$BUFFER
    saved_cursor=$CURSOR
    zle -I
  fi

  local branch
  branch=$(
    git for-each-ref --sort=-committerdate \
      --format='%(refname:short)' refs/heads refs/remotes \
    | grep -vE '^HEAD$' \
    | fzf --height=40% --reverse --prompt='branch> ' \
          --preview='git --no-pager log --graph --oneline --decorate -n 20 {}' \
          --preview-window=down:60%:wrap
  ) || {
    local ret=$?
    if (( in_zle )); then
      BUFFER=$saved_buffer
      CURSOR=$saved_cursor
      zle reset-prompt
    fi
    return $ret
  }

  if [[ $branch == origin/* ]]; then
    git switch -C "${branch#origin/*}" "$branch"
  else
    git switch "$branch"
  fi
}

zle -N gss
bindkey '^k' gss
