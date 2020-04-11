" {{_name_}}
" Author: skanehira
" License: MIT

let s:save_cpo = &cpo
set cpo&vim

{{_cursor_}}

let &cpo = s:save_cpo
unlet s:save_cpo
