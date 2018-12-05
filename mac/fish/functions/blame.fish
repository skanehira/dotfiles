# git blame and git show selected commit
function blame
    if count $argv > /dev/null
        set file $argv[1]
    else
        set file (fzf) 
    end

    if test -z "$file"
        return
    end

    git blame --show-number --color-by-age --color-lines $file | fzf --ansi --tiebreak=index \
        --bind "ctrl-m:execute:
                (grep -o '[a-f0-9]\{7\}' | head -1 |
                xargs -I % sh -c 'git show --color=always % | less -R') << 'FZF-EOF'
                {} FZF-EOF"

end

