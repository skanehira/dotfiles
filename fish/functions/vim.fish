function vim -d 'fzf vim open file'
    if count $argv > /dev/null
        nvim $argv[1]
    else
        fzf | xargs nvim
    end
end
