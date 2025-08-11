-- options
vim.cmd('syntax enable')
vim.cmd('filetype plugin indent on')

vim.g.mapleader = " "
vim.g["markdown_recommended_style"] = 0
vim.opt.breakindent = true
vim.opt.number = false
vim.opt.incsearch = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.hlsearch = true
vim.opt.autoindent = true
vim.opt.smartindent = true
vim.opt.virtualedit = "block"
vim.opt.showtabline = 1
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.softtabstop = 2
vim.opt.completeopt = 'menu,menuone,noselect'
vim.opt.laststatus = 3
vim.opt.scrolloff = 100
vim.opt.cursorline = true
vim.opt.helplang = 'ja'
vim.opt.autowrite = true
vim.opt.swapfile = false
vim.opt.showtabline = 1
vim.opt.diffopt = 'vertical,internal'
vim.opt.clipboard:append({ vim.fn.has('mac') == 1 and 'unnamed' or 'unnamedplus' })
local function is_ssh()
  return os.getenv("SSH_CLIENT") ~= nil or os.getenv("SSH_TTY") ~= nil
end

if is_ssh() then
  vim.g.clipboard = os.getenv("TMUX") and "tmux" or "osc52"
end
vim.opt.grepprg = 'rg --vimgrep'
vim.opt.grepformat = '%f:%l:%c:%m'
vim.opt.mouse = {}
--vim.opt.foldmethod = 'expr'
--vim.opt.foldexpr = 'nvim_treesitter#foldexpr()'

-- persistent undo
local ensure_undo_dir = function()
  local undo_path = vim.fn.expand('~/.config/nvim/undo')
  if vim.fn.isdirectory(undo_path) == 0 then
    vim.fn.mkdir(undo_path --[[@as string]], 'p')
  end
  vim.opt.undodir = undo_path
  vim.opt.undofile = true
end
ensure_undo_dir()

