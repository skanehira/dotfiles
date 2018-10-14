" ====================================== deni.vim settings ======================================

" install dir 
let s:dein_dir = expand('~/.cache/dein') 
let s:dein_repo_dir = s:dein_dir . '/repos/github.com/Shougo/dein.vim'
 
" dein installation check
if &runtimepath !~# '/dein.vim'
 if !isdirectory(s:dein_repo_dir)
 execute '!git clone https://github.com/Shougo/dein.vim' s:dein_repo_dir
 endif
 execute 'set runtimepath^=' . fnamemodify(s:dein_repo_dir, ':p')
endif
 
" begin settings
if dein#load_state(s:dein_dir)
 call dein#begin(s:dein_dir)
 
 " .toml file
 let g:rc_dir = expand('~/.config/nvim')
 let s:toml = g:rc_dir . '/dein.toml'
 let s:lazy_toml = g:rc_dir . '/dein_lazy.toml'
 
 " read toml and cache
 call dein#load_toml(s:toml, {'lazy': 0})
 call dein#load_toml(s:lazy_toml, {'lazy': 1})
 
 " end settings
 call dein#end()
 call dein#save_state()
endif
 
" plugin installation check
if dein#check_install()
 call dein#install()
endif

" ====================================== general customizations ======================================
let mapleader = "\<Space>"
set backspace=2
set smartindent
set number
set tabstop=4
set shiftwidth=4
set expandtab
set incsearch
set hlsearch
set undolevels=100
set clipboard+=unnamed
set scrolloff=999
set relativenumber

nmap <Leader>w :w<CR>
nmap <Leader>q :q!<CR>
nmap <Tab>      gt
nmap <S-Tab>    gT
nmap <C-G><C-G> :vimgrep /<C-R><C-W>/j **/*
nmap <Esc><Esc> :nohlsearch<CR><Esc>
nmap <Leader>p :%s;<C-R><C-W>;

autocmd QuickFixCmdPost *grep* cwindow

" 最後のカーソル位置を復元する
if has("autocmd")
    autocmd BufReadPost *
    \ if line("'\"") > 0 && line ("'\"") <= line("$") |
    \   exe "normal! g'\"" |
    \ endif
endif

" presistent undo
if has('persistent_undo')
  set undodir=~/.vim/undo
  set undofile
endif

" ====================================== vim-go settings ======================================
let g:go_bin_path = $GOPATH.'/bin'
" disable open browser after posting snippet
let g:go_play_open_browser = 0
" enable goimports
let g:go_fmt_command = "goimports"
let g:go_metalinter_autosave = 1
let g:go_metalinter_autosave_enabled = ['vet']
let g:go_highlight_types = 1
let g:go_highlight_fields = 1
let g:go_highlight_functions = 1
let g:go_highlight_methods = 1
let g:go_highlight_structs = 1
let g:go_highlight_function_calls = 1
let g:go_term_mode = 'split'

"au FileType go nmap <leader>r <Plug>(go-run)
"au FileType go nmap <Leader>s <Plug>(go-def-split)
"au FileType go nmap <Leader>v <Plug>(go-def-vertical)
"au FileType go nmap <leader>s <Plug>(go-def-split)
"au FileType go nmap <leader>v <Plug>(go-def-vertical)
au FileType go nmap <silent> <leader>t <Plug>(go-test)
au FileType go nmap <silent> <leader>c <Plug>(go-coverage)
au FileType go nmap <silent> <leader>at :GoAddTags<CR>
au FileType go nmap <silent> <leader>rt :GoRemoveTags<CR>
au FileType go nmap <silent> <leader>fs :GoFillStruct<CR>
au FileType go nmap <silent> <leader>ie :GoIfErr<CR>
au FileType go nmap <silent> <leader>ki :GoKeyify<CR>
au FileType go nmap <silent> <leader>dd :GoDeclsDir<CR>
au FileType go nmap <silent> <leader>dl :GoDecls<CR>
au FileType go nmap <silent> <leader>ip :GoImpl<CR>
au FileType go nmap <silent> <leader>rn :GoRename<CR>
au FileType go :highlight goErr cterm=bold ctermfg=214
au FileType go :match goErr /\<err\>/

" ====================================== nerdtree settings ======================================
let NERDTreeShowBookmarks=1
nnoremap <silent><C-n> :NERDTreeToggle<CR>

" ====================================== vim-gitgutter settings ======================================
set signcolumn=yes
set updatetime=250
"let g:gitgutter_highlight_lines = 1
"highlight GitGutterAddLine ctermfg=darkblue ctermbg=black
"highlight GitGutterChangeLine  ctermfg=darkblue ctermbg=black
"highlight GitGutterDeleteLine   ctermfg=black ctermbg=darkred

" ====================================== fzf settings ======================================
nmap <C-P> :Files<CR>

" ====================================== airline settings ======================================
let g:airline_powerline_fonts = 1
let g:airline#extensions#tabline#enabled = 1
let g:airline#extensions#tabline#show_splits = 0
let g:airline#extensions#tabline#show_tab_type = 0
let g:airline#extensions#tabline#show_close_button = 0

" ====================================== lsp golang settings ======================================
if executable('go-langserver')
    au User lsp_setup call lsp#register_server({
        \ 'name': 'go-langserver',
        \ 'cmd': {server_info->['go-langserver', '-mode', 'stdio']},
        \ 'whitelist': ['go'],
        \ })
endif

au FileType go nmap <silent> <Leader>d :LspDefinition<CR>
au FileType go nmap <silent> <Leader>p :LspHover<CR>
au FileType go nmap <silent> <Leader>r :LspReferences<CR>
au FileType go nmap <silent> <Leader>i :LspImplementation<CR>
au FileType go nmap <silent> <Leader>s :split \| :LspDefinition <CR>
au FileType go nmap <silent> <Leader>v :vsplit \| :LspDefinition <CR>

let g:lsp_signs_error = {'text': '✗'}
let g:lsp_signs_error = {'text': '!!'}
let g:lsp_signs_enabled = 1         " enable signs
let g:lsp_diagnostics_echo_cursor = 1 " enable echo under cursor when in normal mode

" ====================================== vim-markdown settings ======================================
let g:vim_markdown_folding_disabled = 1

" ====================================== vim-surround settings ======================================
nmap <Leader>7 ysiw'<CR>
nmap <Leader>2 ysiw"<CR>
nmap <Leader>8 ysiw(<CR>
nmap <Leader>[ ysiw[<CR>

" ====================================== ultisnips settings ======================================
let g:UltiSnipsExpandTrigger="<c-f>"
let g:UltiSnipsJumpForwardTrigger="<c-f>"
