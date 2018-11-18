function commit -d 'git add and commit files'
    if count $argv > /dev/null
        git add .
        git commit -m $argv[1]
    else
        echo 'Usage: commit "comment"'
    end
end
