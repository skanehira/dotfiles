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

    set id (git blame --show-number --color-by-age --color-lines $file | fzf --ansi --tiebreak=index | cut -f1 -d ' ')

    set log (git log --oneline $id | head -n 1)

    set merge (echo $log | grep 'Merge pull request #')
    if test -z "$merge"
      set squash (echo $log | grep '#\d')
      if test -z "$squash"
        return
      end
      set pr (git log --oneline $id | sed -n 1P | sed 's/\(.*(#\)\(.*\))/pull\/\2/')
    else
      set pr (echo $merge | cut -f5 -d ' ' | sed -e 's%#%pull/%')
    end
    if test -z "$pr"
      return
    end

    set remote (git remote get-url --push origin | sed 's/\(ssh:\/\/git@\)\(.*\)\.git/https:\/\/\2/')
    if test -z "$remote"
      return
    end

    echo $remote/$pr
end

