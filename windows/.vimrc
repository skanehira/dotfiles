" ====================================== dein.vim settings ======================================
" install dir
let s:dein_dir = expand('‾/.cache/dein')
let s:dein_repo_dir = s:dein_dir . '/repos/github.com/Shougo/dein.vim'

" dein installation check
if &runtimepath !‾# '/dein.vim'
 if !isdirectory(s:dein_repo_dir)
 execute '!git clone https://github.com/Shougo/dein.vim' s:dein_repo_dir
 endif
 execute 'set runtimepath^=' . s:dein_repo_dir
endif

" begin settings
if dein#load_state(s:dein_dir)
 call dein#begin(s:dein_dir)

 " .toml file
 let s:rc_dir = expand('‾/.vim')
 let s:toml = s:rc_dir . '/dein.toml'
 let s:lazy_toml = s:rc_dir . '/dein_lazy.toml'

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

" ====================================== general settings ======================================
" vim scriptでマルチバイト文字を使用しているため設定
scriptencoding utf-8

" ミュートにする。
set t_vb=
set visualbell
set noerrorbells

" 文字コード
set encoding=utf-8
set fileencodings=utf-8,iso-2022-jp,euc-jp,sjis
set fileformats=unix,dos,mac

" https://vim-jp.org/vimdoc-ja/map.html#mapleader
" Leaderキーをスペースに設定
let g:mapleader = "¥<Space>"

" シンタックスを有効にする
syntax enable

" カラースキームを使う
colorscheme iceberg

" https://vim-jp.org/vimdoc-ja/filetype.html#:filetype-plugin-on
" https://vim-jp.org/vimdoc-ja/filetype.html#:filetype-indent-on
" ファイル形式別プラグインとインデントを有効にする
" これがないとvim-goなどが動作しない
filetype plugin indent on

" バックスペースとCtrl+hで削除を有効にする
set backspace=2

" 改行時自動インデント
set smartindent

" 行番号を表示
set number

" カーソルから相対的な行数を表示する
set relativenumber

" https://vim-jp.org/vimdoc-ja/options.html#'tabstop'
" タブでも常に空白を挿入
set tabstop=4
set shiftwidth=4
set expandtab

" インクリメントサーチを有効にする
set incsearch

" https://vim-jp.org/vimdoc-ja/options.html#'ignorecase'
" 検索時大文字小文字を区別しない
set ignorecase

" https://vim-jp.org/vimdoc-ja/options.html#'smartcase'
" 検索時に大文字を入力した場合ignorecaseが無効になる
set smartcase

" ハイライトサーチを有効にする
set hlsearch

" undoできる最大数
set undolevels=1000

" mac os のクリップボードを共有
set clipboard+=unnamed

" カーソルが常に中央に来るようにする
set scrolloff=100

" スワップファイルに書き込まれる時間(ミリ秒単位)
set updatetime=450

" マクロで効果発揮
set lazyredraw
set ttyfast

" 一行が長いファイルをsyntaxを制御することで軽くする
set synmaxcol=256

" カーソルラインを表示する
set cursorline

" *でカーソルを移動しないようにする
noremap * *N

" https://vim-jp.org/vimdoc-ja/pi_netrw.html#g:netrw_liststyle
" netrwツリー表示を有効にする
let g:netrw_liststyle=1
let g:netrw_banner=0
let g:netrw_sizestyle="H"
let g:netrw_timefmt="%Y/%m/%d(%a) %H:%M:%S"
let g:netrw_preview=1

" 拡張子ごとのインデントを指定する
augroup fileTypeIndent
    autocmd!
    au BufRead,BufNewFile *.html setlocal tabstop=4 softtabstop=4 shiftwidth=4
    au BufRead,BufNewFile *.js   setlocal tabstop=2 softtabstop=2 shiftwidth=2
    au BufRead,BufNewFile *.vue  setlocal tabstop=2 softtabstop=2 shiftwidth=2
augroup END

" https://vim-jp.org/vimdoc-ja/options.html#'wildmode'
" wildmenuを有効にする
set wildmenu
set wildmode=full

" grepした結果をquickfixに表示する
augroup grepwindow
    autocmd!
    au QuickFixCmdPost *grep* cwindow
augroup END

" カーソルラインの位置を保存する
if has("autocmd")
    autocmd BufReadPost *
    ¥ if line("'¥"") > 0 && line ("'¥"") <= line("$") |
    ¥   exe "normal! g'¥"" |
    ¥ endif
endif

" undoの保存先
if has('persistent_undo')
  set undodir=‾/.vim/undo
  set undofile
endif

" visualモードのハイライトカラー
hi Visual cterm=reverse ctermbg=NONE

" バックアップしない
set noswapfile
set nobackup

" ====================================== key mappings ======================================
" ファイル保存と終了
nnoremap <Leader>w :w<CR>
nnoremap <Leader>q :q!<CR>

" 検索
nnoremap <C-G><C-G> :Ggrep <C-R><C-W><CR><CR>

" 置換
nnoremap <Leader>re :%s;<C-R><C-W>;g<Left><Left>;

" visualで選択したテキストを置換する
vnoremap <Leader>re y:%s;<C-r>=substitute(@", "<C-v><NL>", "¥¥¥¥n", "g")<CR>;;g<Left><Left>

" ハイライトを削除する
nnoremap <Esc><Esc> :nohlsearch<CR>

" 画面移動
"nnoremap <C-H> <C-W>h
"nnoremap <C-J> <C-W>j
"nnoremap <C-K> <C-W>k
"nnoremap <C-L> <C-W>l

" vimrcを開く
nnoremap <Leader>. :e ‾/_vimrc<CR>

" Ctrl+cでnormalモード
nnoremap <C-c> <Esc>
cnoremap <C-c> <Esc>
vnoremap <C-c> <Esc>

" text object key mapping
onoremap 8 i(
onoremap 2 i"
onoremap 7 i'
onoremap @ i`
onoremap [ i[
onoremap { i{

onoremap a8 a(
onoremap a2 a"
onoremap a7 a'
onoremap a@ a`
onoremap a[ a[
onoremap a{ a{

" visual
nnoremap v8 vi(
nnoremap v2 vi"
nnoremap v7 vi'
nnoremap v@ vi`
nnoremap v[ vi[
nnoremap v{ vi{

nnoremap va8 va(
nnoremap va2 va"
nnoremap va7 va'
nnoremap va@ va`
nnoremap va[ va[
nnoremap va{ va{

" 数値の+-
nnoremap + <C-a>
nnoremap - <C-x>

" 行先頭と行末
map H ^
map L $

" タブ切り替え
nnoremap <Tab> gt
nnoremap <S-Tab> gT

" visual時に選択行を移動
vnoremap <C-j> :m '>+1<CR>gv=gv
vnoremap <C-k> :m '<-2<CR>gv=gv

" numberとrelativenumberの切り替え
nnoremap <silent> <Leader>n :set relativenumber!<CR>

" visual paste
vnoremap <silent> <C-p> "0p<CR>

" ターミナルを下部で開く
nnoremap <silent> <Leader>te :belowright term<cr>

" コマンドウィンドウを開く
"nnoremap : :<C-f>i

" 画面分割
nnoremap <leader>s :vs<CR>
nnoremap <leader>v :sp<CR>

" 上下の空白に移動
nnoremap <C-j> }
nnoremap <C-k> {

" 検索でvery magicを使用する
nnoremap /  /¥v

" netrwを開く
nnoremap <leader>e :Vexplore<CR>

" fzf
nnoremap <c-p> :Files<CR>

" ====================================== asyncomplete settings ======================================
inoremap <expr> <C-j> pumvisible() ? "¥<C-n>" : "¥<Tab>"
inoremap <expr> <C-k> pumvisible() ? "¥<C-p>" : "¥<S-Tab>"
inoremap <expr> <CR> pumvisible() ? "¥<C-y>" : "¥<cr>"

" ====================================== vim-markdown settings ======================================
" mdを開くときの折りたたみを無効にする
let g:vim_markdown_folding_disabled = 1

" ====================================== vim-surround settings ======================================
nmap <Leader>7 ysiw'
nmap <Leader>2 ysiw"
nmap <Leader>` ysiw`
nmap <Leader>8 ysiw)
nmap <Leader>[ ysiw]
nmap <Leader>{ ysiw}

" ====================================== profiling ======================================
" vim +'call ProfileCursorMove()' <カーソルを動かすのが重いファイル>
function! ProfileCursorMove() abort
  let profile_file = expand('./vim-profile.log')
  if filereadable(profile_file)
    call delete(profile_file)
  endif

  normal! ggzR

  execute 'profile start ' . profile_file
  profile func *
  profile file *

  augroup ProfileCursorMove
    autocmd!
    autocmd CursorHold <buffer> profile pause | q
  augroup END

  for i in range(1000)
    call feedkeys('j')
  endfor
endfunction

" ====================================== lightline ======================================
set laststatus=2
if !has('gui_running')
  set t_Co=256
endif