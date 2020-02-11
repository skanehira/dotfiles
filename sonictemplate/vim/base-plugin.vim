" {{_name_}}
" Author: skanehira
" License: MIT

if exists('loaded_{{_name_}}')
  finish
endif
let g:loaded_{{_name_}} = 1

let s:save_cpo = &cpo
set cpo&vim



let &cpo = s:save_cpo
unlet s:save_cpo
