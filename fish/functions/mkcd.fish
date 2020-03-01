function mkcd -d "make and cd dir"
    set dir $argv[1]
    if [ "$dir" != "" ]
        mkdir -p $dir
        cd $dir
    end
end
