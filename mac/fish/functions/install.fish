function install
    set token (brew search | fzf --query=$argv[1])

    if [ (echo "x$token") != "x" ]
        brew install $token
    end
end
