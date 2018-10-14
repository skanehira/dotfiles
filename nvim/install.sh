#!/bin/bash
path=~/.config/nvim

if [ ! -e $path ]; then
	echo "create directory $path"
    mkdir -p $path
fi

cp -Rp `ls | grep -v *.sh` $path/
