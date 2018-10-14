function cm -d 'git add and commit files'
    if count $argv > /dev/null
        git add .
        git commit -m $argv[1]
    else
        echo 'Usage: cm comment'
    end
end
