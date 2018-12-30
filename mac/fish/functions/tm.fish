function tm -d "attach or new tmux sessions"
  test -n "$TMUX" && set change "switch-client" ;or set change "attach-session"
  if count $argv > /dev/null
    tmux $change -t $argv[1] 2>/dev/null ;or tmux new-session -d -s $argv[1] && tmux $change -t $argv[1]; return
  end
  set session (tmux list-sessions -F "#{session_name}" 2>/dev/null | fzf --exit-0) && tmux $change -t "$session" ;or echo "No sessions found."
end
