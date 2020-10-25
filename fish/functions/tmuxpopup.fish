function tmuxpopup -d "toggle tmux popup window"
  set width '80%'
  set height '80%'
  set session (tmux display-message -p -F "#{session_name}")
  if contains "popup" $session
    tmux detach-client
  else
    tmux popup -d '#{pane_current_path}' -xC -yC -w$width -h$height -K -E -R "tmux attach -t popup || tmux new -s popup"
  end
end
