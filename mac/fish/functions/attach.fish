function attach
    set container (docker ps --format "{{.ID}} {{.Names}}" | fzf)

    if [ "$container" != "" ]
        set id (echo "$container" | awk "{print \$1}")
        set cmd (read -P "cmd:")
        docker exec -it $id $cmd
    end
end

