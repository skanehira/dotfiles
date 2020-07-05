function fish_user_key_bindings
  fzf_key_bindings

  for mode in insert default visual
    # restore some keys
    # https://github.com/fish-shell/fish-shell/issues/3541
    # https://qiita.com/ryotako/items/ba7483b6fde025c91cef
    bind -M $mode \cf forward-char
    bind -M $mode \cb backward-char
    bind -M $mode \ck kill-line
    bind -M $mode \cp history-search-backward
    bind -M $mode \cn history-search-forward
    bind -M $mode \ca beginning-of-line
    bind -M $mode \ce end-of-line
    bind -M $mode \cd delete-or-exit
    bind -M $mode \cu backward-kill-line

    # restore fzf keybinding
    # https://github.com/junegunn/fzf/blob/3918c45ceda5e7c57d6832cdeedbfeb8f7a6444e/shell/key-bindings.fish#L94-L96
    bind -M $mode \ct fzf-file-widget
    bind -M $mode \cr fzf-history-widget
  end
end

