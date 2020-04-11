function attach
    set container (docker ps --format "{{.ID}} {{.Names}}" | fzf)

    if [ "$container" != "" ]
        set id (echo "$container" | awk "{print \$1}")
        docker exec -it $id sh -c "[ -e /bin/bash ] && /bin/bash || sh"
    end
end

