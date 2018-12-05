function rec
    if count $argv > /dev/null
        asciinema rec -t $argv[1]
    else
        echo 'Usage: rec title'
    end
end

