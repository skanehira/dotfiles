function push
    if count $argv > /dev/null
        git push origin $argv[1]
    else
        git push origin
    end
end

