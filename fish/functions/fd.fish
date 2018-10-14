# fd - cd to selected directory
function fd -d 'selected directory'
  set dir .
  if count $argv > /dev/null
    set dir $argv[1]
  end

  set dir (find $dir -path '*/\.*' -prune \
                  -o -type d -print 2> /dev/null | fzf +m); and cd "$dir"
end

