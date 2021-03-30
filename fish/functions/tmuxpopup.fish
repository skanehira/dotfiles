function tmuxpopup -d "toggle tmux popup window"
  set width '90%'
  set height '90%'

  if count $argv > /dev/null
    tmux popup -d '#{pane_current_path}' -xC -yC -w$width -h$height -E $argv[1]
  else
    set session (tmux display-message -p -F "#{session_name}")
    if contains "popup" $session
      tmux detach-client
    else
      tmux popup -d '#{pane_current_path}' -xC -yC -w$width -h$height -E "tmux attach -t popup || tmux new -s popup"
    end
  end

end
