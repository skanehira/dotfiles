function fvim -d 'fzf vim open file'
    if count $argv > /dev/null
        vim $argv[1]
    else
        vim (fzf)
    end
end
