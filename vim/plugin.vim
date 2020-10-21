" {{{ dein.vim settings
let s:dein_dir = expand('~/.cache/dein')
let s:dein_repo_dir = s:dein_dir . '/repos/github.com/Shougo/dein.vim'

if &runtimepath !~# '/dein.vim'
  if !isdirectory(s:dein_repo_dir)
    execute '!git clone https://github.com/Shougo/dein.vim' s:dein_repo_dir
  endif
  execute 'set runtimepath^=' . s:dein_repo_dir
endif

if dein#load_state(s:dein_dir)
  call dein#begin(s:dein_dir, [expand('~/.plugin.vim')])

  let s:tokenfile = expand('~/.gh-vim')
  if filereadable(s:tokenfile)
    let g:dein#install_github_api_token = trim(readfile(s:tokenfile)[0])
  endif

  " add plugins
  call dein#add('LeafCage/vimhelpgenerator')
  call dein#add('Shougo/dein.vim')
  call dein#add('airblade/vim-gitgutter')
  call dein#add('andymass/vim-matchup')
  call dein#add('basyura/TweetVim')
  call dein#add('basyura/twibill.vim')
  call dein#add('bronson/vim-trailing-whitespace')
  call dein#add('cespare/vim-toml')
  call dein#add('cocopon/iceberg.vim')
  call dein#add('cohama/lexima.vim')
  call dein#add('ctrlpvim/ctrlp.vim')
  call dein#add('dag/vim-fish')
  call dein#add('fatih/vim-go')
  call dein#add('ghifarit53/tokyonight-vim')
  call dein#add('glidenote/memolist.vim')
  call dein#add('godlygeek/tabular')
  call dein#add('gyim/vim-boxdraw')
  call dein#add('itchyny/lightline.vim')
  call dein#add('kana/vim-operator-replace')
  call dein#add('kana/vim-operator-user')
  call dein#add('kshenoy/vim-signature')
  call dein#add('lambdalisue/fern.vim')
  call dein#add('lambdalisue/gina.vim')
  call dein#add('markonm/traces.vim')
  call dein#add('mattn/ctrlp-matchfuzzy')
  call dein#add('mattn/emmet-vim')
  call dein#add('mattn/gist-vim')
  call dein#add('mattn/sonictemplate-vim')
  call dein#add('mattn/vim-lsp-settings', {'merged': 0})
  call dein#add('mattn/vim-maketable')
  call dein#add('mattn/webapi-vim')
  call dein#add('plasticboy/vim-markdown')
  call dein#add('posva/vim-vue')
  call dein#add('prabirshrestha/vim-lsp')
  call dein#add('previm/previm')
  call dein#add('shinespark/vim-list2tree')
  call dein#add('simeji/winresizer')
  call dein#add('skanehira/code2img.vim')
  call dein#add('skanehira/docker.vim')
  call dein#add('skanehira/preview-markdown.vim')
  call dein#add('skanehira/translate.vim')
  call dein#add('thinca/vim-quickrun')
  call dein#add('thinca/vim-themis')
  call dein#add('tokorom/vim-review')
  call dein#add('tweekmonster/helpful.vim')
  call dein#add('tyru/open-browser-github.vim')
  call dein#add('tyru/open-browser.vim')
  call dein#add('vim-jp/vimdoc-ja')
  call dein#add('vim-jp/vital.vim', {'merged': 0})

  " end settings
  call dein#end()
  call dein#save_state()
endif

if dein#check_install()
  call dein#install()
endif

let s:removed_plugins = dein#check_clean()
if len(s:removed_plugins) > 0
  call map(s:removed_plugins, "delete(v:val, 'rf')")
  call dein#recache_runtimepath()
endif
" }}}

" {{{ netrw
let g:netrw_liststyle=3
let g:netrw_banner=0
let g:netrw_sizestyle='H'
let g:netrw_timefmt='%Y/%m/%d(%a) %H:%M:%S'
" }}}

" {{{ translate.vim
nmap gr <Plug>(Translate)
vmap gt <Plug>(VTranslate)
" }}}

" {{{ fern.vim
function! s:fern_init() abort
  let g:fern#disable_viewer_hide_cursor = 1
  nnoremap <buffer> <silent> q :q<CR>
  map <buffer> <silent> <C-v> <Plug>(fern-action-open:split)
endfunction

augroup fern-setteings
  au!
  au FileType fern call s:fern_init()
augroup END

nnoremap <silent> <Leader>f :Fern . -drawer<CR>
" }}}

" {{{ gina.vim
call gina#custom#mapping#nmap(
      \ 'status', 'gp',
      \ ':<C-u>Gina push<CR>',
      \ {'noremap': 1, 'silent': 1},
      \)
call gina#custom#mapping#nmap(
      \ 'status', 'cm',
      \ ':<C-u>Gina commit<CR>',
      \ {'noremap': 1, 'silent': 1},
      \)
call gina#custom#mapping#nmap(
      \ 'status', 'ca',
      \ ':<C-u>Gina commit --amend<CR>',
      \ {'noremap': 1, 'silent': 1},
      \)
call gina#custom#mapping#nmap(
      \ 'status', 'dp',
      \ '<Plug>(gina-patch-oneside-tab)',
      \ {'silent': 1},
      \)
call gina#custom#mapping#nmap(
      \ 'status', 'ga',
      \ '--',
      \ {'silent': 1},
      \)
call gina#custom#mapping#vmap(
      \ 'status', 'ga',
      \ '--',
      \ {'silent': 1},
      \)
call gina#custom#mapping#nmap(
      \ 'log', 'dd',
      \ '<Plug>(gina-changes-of)',
      \ {'silent': 1},
      \)
call gina#custom#mapping#nmap(
      \ 'branch', 'n',
      \ '<Plug>(gina-branch-new)',
      \ {'silent': 1},
      \)
call gina#custom#mapping#nmap(
      \ '/.*', 'q',
      \ ':<C-u>bw!<CR>',
      \ {'noremap': 1, 'silent': 1},
      \)

nnoremap <silent> gs :Gina status -s<CR>
nnoremap <silent> gl :Gina log<CR>
nnoremap <silent> gm :Gina blame<CR>
nnoremap <silent> gb :Gina branch<CR>
" }}}

" {{{ quickrun.vim
nnoremap <Leader>q :QuickRun<CR>
" }}}

" {{{ code2img.vim
let g:code2img_line_number = 1
map gi <Plug>(Code2img)
xmap gi <Plug>(Code2img)
" }}}

" vim-go settings {{{
let g:go_fmt_command = 'goimports' " ファイル保存時go importを実行する
let g:go_gopls_enabled = 0 " goplsを有効化
let g:go_def_mapping_enabled = 0 " vim-lspを使用するので、vim-goの`Ctrl+]`を無効にする
let g:go_template_autocreate = 0 " テンプレート作成を無効化
let g:go_def_reuse_buffer = 1 " すでに開いているバッファに定義ジャンプする
let g:go_fold_enable = ['block', 'import', 'varconst', 'package_comment']
augroup vim-go-fold
  au!
  au FileType go set foldmethod=syntax
augroup END
" }}}

" fzf settings {{{
command! -bang -nargs=? -complete=dir Files
      \ call fzf#vim#files(<q-args>, fzf#vim#with_preview(), <bang>0)
nnoremap <C-P> :Files<CR>
" }}}

" lsp settings {{{
let g:lsp_signs_error = {'text': 'ｳﾎ'}
let g:lsp_signs_warning = {'text': '🍌'}
let g:lsp_diagnostics_float_cursor = 1
"let g:lsp_log_verbose = 1
let g:lsp_log_file = expand('~/vim-lsp.log')

nmap <Leader>ho <plug>(lsp-hover)
nnoremap <silent> <C-]> :LspDefinition<CR>

let g:lsp_settings = {
      \ 'gopls': {
      \  'workspace_config': {
      \    'usePlaceholders': v:true,
      \    'analyses': {
      \      'fillstruct': v:true,
      \    },
      \  },
      \  'initialization_options': {
      \    'usePlaceholders': v:true,
      \    'analyses': {
      \      'fillstruct': v:true,
      \    },
      \  },
      \ },
      \ 'eslint-language-server': {
      \   'allowlist': ['javascript', 'typescript', 'vue'],
      \ },
      \ 'efm-langserver': {
      \   'disabled': 0,
      \   'allowlist': ['markdown'],
      \  }
      \}

let g:lsp_settings_filetype_typescript = ['typescript-language-server', 'eslint-language-server']

function! s:on_lsp_buffer_enabled() abort
  setlocal completeopt=menu
  setlocal omnifunc=lsp#complete
  let g:lsp_settings_root_markers = ['go.mod'] + g:lsp_settings_root_markers
endfunction

augroup lsp_install
  au!
  au User lsp_buffer_enabled call s:on_lsp_buffer_enabled()
augroup END
" }}}

" vim-markdown {{{
let g:vim_markdown_folding_disabled = 1
" }}}

" emmet {{{
let g:user_emmet_install_global = 0
let g:user_emmet_settings = {
      \   'variables': {
      \     'lang' : 'ja'
      \   }
      \ }
let g:user_emmet_leader_key = '<C-g>'

augroup emmet
  au!
  au FileType vue,html,css EmmetInstall
  au FileType vue,html,css imap <buffer> <C-f> <plug>(emmet-expand-abbr)
augroup END
" }}}

" vim-vue {{{
" https://github.com/posva/vim-vue#my-syntax-highlighting-stops-working-randomly
" vueファイルのシンタックスが効かなくなる問題対応
augroup VueSyntax
  au!
  au FileType vue syntax sync fromstart
augroup END
" }}}

" sonictemplate.vim {{{
let g:sonictemplate_vim_template_dir = ["~/.vim/template"]
let g:sonictemplate_author = 'skanehira'
let g:sonictemplate_license = 'MIT'
let g:sonictemplate_vim_template_dir = expand('~/.vim/sonictemplate')
imap <silent> <C-l> <plug>(sonictemplate-postfix)
" }}}

" vimhelpgenarator {{{
let g:vimhelpgenerator_version = ''
let g:vimhelpgenerator_author = 'Author: skanehira <sho19921005@gmail.com>'
let g:vimhelpgenerator_uri = 'https://github.com/skanehira/'
let g:vimhelpgenerator_defaultlanguage = 'en'
" }}}

" {{{ MemoList
let g:memolist_fzf = 1
" }}}

" {{{ lexima
let g:lexima_enable_basic_rules = 1
" }}}

" {{{ docker.vim
let g:docker_use_tmux = 1
" }}}

" {{{ preview.vim
let g:previm_open_cmd = 'open'
let g:previm_plantuml_imageprefix = 'http://localhost:8888/png/'
" }}}

" {{{ preview-markdown.vim
let g:preview_markdown_vertical = 1
let g:preview_markdown_auto_update = 1
" }}}

"{{{ gist-vim
let g:gist_post_private = 1
let g:gist_list_vsplit = 1
"}}}

" {{{ tweetvim
let g:tweetvim_display_time = 1
let g:tweetvim_open_buffer_cmd = 'tabnew'
nnoremap <silent> <Leader>th :<C-u>TweetVimHomeTimeline<CR>
nnoremap <silent> <Leader>ts :<C-u>TweetVimSay<CR>
nnoremap <silent> <Leader>tm :<C-u>TweetVimMentions<CR>
" }}}

" {{{ gh.vim
let gh_token_file = expand('~/.gh-vim')
if filereadable(gh_token_file)
  let g:gh_token = trim(readfile(gh_token_file)[0])
  let g:gh_enable_delete_repository = 0

  function! s:gh_map_apply() abort
    call gh#map#add('gh-buffer-issue-list', 'map', 'e', '<Plug>(gh_issue_edit)')
    call gh#map#add('gh-buffer-issue-list', 'map', 'gm', '<Plug>(gh_issue_open_comment)')
    call gh#map#add('gh-buffer-issue-comment-list', 'map', 'n', '<Plug>(gh_issue_comment_new)')
    call gh#map#add('gh-buffer-issue-edit', 'map', 'gm', '<Plug>(gh_issue_comment_open_on_issue)')
  endfunction

  augroup gh-maps
    au!
    au VimEnter * call <SID>gh_map_apply()
  augroup END
endif
" }}}

" {{{ ctrlp
let g:ctrlp_match_func = {'match': 'ctrlp_matchfuzzy#matcher'}
let g:ctrlp_custom_ignore = 'node_modules'
let g:ctrlp_mruf_default_order = 1
let g:ctrlp_prompt_mappings = {
      \ 'MarkToOpen()':         ['<C-z>', '<C-q>'],
      \ }
" }}}

" {{{ lightline
let g:lightline = {
      \ 'colorscheme': 'tokyonight',
      \ 'active': {
      \ 'left': [ ['mode', 'paste'], ['readonly', 'filepath', 'modified'] ]
      \ },
      \ 'component_function':{
      \ 'filepath': 'FilePath',
      \ },
      \ }

function! FilePath()
  if winwidth(0) > 90
    return expand("%:s")
  else
    return expand("%:t")
  endif
endfunction

" # show statusbar
set laststatus=2
" # hide --INSERT--
set noshowmode
" }}}

" {{{ vim-trailing-whitespace
let g:extra_whitespace_ignored_filetypes = ['fern', 'markdown']
" }}}

" {{{ vim-operator-replace
if !has('mac')
  vmap p <Plug>(operator-replace)
endif
" }}}

" vim: foldmethod=marker
