function tmuxpopup() {
  local width='90%'
  local height='90%'

  if [ -n "$1" ];then
    tmux popup -d '#{pane_current_path}' -xC -yC -w$width -h$height -E $1
    return
  fi

  local name=$(tmux display-message -p -F "#{session_name}")
  if [[ $name =~ 'popup' ]];
  then
    tmux detach-client
  else
    tmux popup -d '#{pane_current_path}' -xC -yC -w$width -h$height -E "tmux new -A -s popup"
  fi
}
zle -N tmuxpopup
