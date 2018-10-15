function ftmux
    if [ (echo $TMUX) = "" ]
        tmux list-sessions
            if test $status = 0
                tmux attach -t (tmux list-sessions | fzf | cut -d ":" -f 1)
                #echo $ids | fzf
            else
                tmux new-session
            end
    end
end
