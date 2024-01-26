local map = function(mode, lhs, rhs, opt)
  vim.keymap.set(mode, lhs, rhs, opt or { silent = true })
end

local keymaps = {
  map = map,
}

for _, mode in pairs({ 'n', 'v', 'i', 'o', 'c', 't', 'x', 't' }) do
  keymaps[mode .. 'map'] = function(lhs, rhs, opt)
    map(mode, lhs, rhs, opt)
  end
end

local nmap = keymaps.nmap
local omap = keymaps.omap
local imap = keymaps.imap
local xmap = keymaps.xmap
local cmap = keymaps.cmap
local tmap = keymaps.tmap
local vmap = keymaps.vmap

-- text object
omap('8', 'i(')
omap('2', 'i"')
omap('7', 'i\'')
omap('@', 'i`')
omap('[', 'i[')
omap('{', 'i{')
omap('a8', 'a(')
omap('a2', 'a"')
omap('a7', 'a\'')
omap('a@', 'a`')

nmap('v8', 'vi(')
nmap('v2', 'vi"')
nmap('v7', 'vi\'')
nmap('v@', 'vi`')
nmap('v[', 'vi[')
nmap('v{', 'vi{')
nmap('va8', 'va(')
nmap('va2', 'va"')
nmap('va7', 'va\'')
nmap('va@', 'va`')

-- emacs like
imap('<C-k>', '<C-o>C')
imap('<C-f>', '<Right>')
imap('<C-b>', '<Left>')
imap('<C-e>', '<C-o>A')
imap('<C-a>', '<C-o>I')

xmap("*",
  table.concat {
    -- 選択範囲を検索クエリに用いるため、m レジスタに格納。
    -- ビジュアルモードはここで抜ける。
    [["my]],
    -- "m レジスタの中身を検索。
    -- ただし必要な文字はエスケープした上で、空白に関しては伸び縮み可能とする
    [[/\V<C-R><C-R>=substitute(escape(@m, '/\'), '\_s\+', '\\_s\\+', 'g')<CR><CR>]],
    -- 先ほど検索した範囲にカーソルが移るように、手前に戻す
    [[N]],
  },
  {}
)

-- command line
-- cmap defaults silent to true, but passes an empty setting because the cursor is not updated
cmap('<C-b>', '<Left>', {})
cmap('<C-f>', '<Right>', {})
cmap('<C-a>', '<Home>', {})
cmap('<Up>', '<C-p>')
cmap('<Down>', '<C-n>')
cmap('<C-n>', function()
  return vim.fn.pumvisible() == 1 and '<C-n>' or '<Down>'
end, { expr = true })
cmap('<C-p>', function()
  return vim.fn.pumvisible() == 1 and '<C-p>' or '<Up>'
end, { expr = true })
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'qf',
  callback = function()
    nmap('q', '<Cmd>q<CR>', { silent = true, buffer = true })
  end,
  group = vim.api.nvim_create_augroup("qfInit", { clear = true }),
})

-- paste with <C-v>
map({ 'c', 'i' }, '<C-v>', 'printf("<C-r><C-o>%s", v:register)', { expr = true })

-- other keymap
nmap('<Leader>.', ':tabnew ~/.config/nvim/init.lua<CR>')
nmap('Y', 'Y')
nmap('R', 'gR')
nmap('*', '*N')
nmap('<Esc><Esc>', '<Cmd>nohlsearch<CR>')
nmap('H', '^')
nmap('L', 'g_')
nmap('<C-j>', 'o<Esc>')
nmap('<C-k>', 'O<Esc>')
nmap('o', 'A<CR>')
nmap('<C-l>', 'gt')
nmap('<C-h>', 'gT')
nmap('<Leader>tm', [[:new | terminal<CR>]])
tmap('<C-]>', [[<C-\><C-n>]])
vmap('H', '^')
vmap('L', 'g_')

return keymaps
