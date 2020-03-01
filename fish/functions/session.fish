function session -d "vim session"
   set target (finder ~/.vim/sessions | fzf)
   if test -e $target 
        vim -S $target
   end
end

