---@diagnostic disable: redundant-parameter

-- disable default plugins
local disable_plugins = {
  "loaded_gzip",
  "loaded_shada_plugin",
  "loadedzip",
  "loaded_spellfile_plugin",
  "loaded_tutor_mode_plugin",
  "loaded_gzip",
  "loaded_tar",
  "loaded_tarPlugin",
  "loaded_zip",
  "loaded_zipPlugin",
  "loaded_rrhelper",
  "loaded_2html_plugin",
  "loaded_vimball",
  "loaded_vimballPlugin",
  "loaded_getscript",
  "loaded_getscriptPlugin",
  "loaded_logipat",
  "loaded_matchparen",
  "loaded_man",
  "loaded_netrw",
  "loaded_netrwPlugin",
  "loaded_netrwSettings",
  "loaded_netrwFileHandlers",
  "loaded_logiPat",
  "did_install_default_menus",
  "did_install_syntax_menu",
  "skip_loading_mswin",
}

for _, name in pairs(disable_plugins) do
  vim.g[name] = true
end

-- lsp global settings
require('my/settings/lsp')

-- keymaps
local keymaps = require('my/settings/keymaps')
local map = keymaps.map

-- options
require('my/settings/options')

-- file indent
local filetype_indent_group = vim.api.nvim_create_augroup('fileTypeIndent', { clear = true })
local file_indents = {
  {
    pattern = 'go',
    command = 'setlocal tabstop=4 shiftwidth=4'
  },
  {
    pattern = 'rust',
    command = 'setlocal tabstop=4 softtabstop=4 shiftwidth=4 expandtab'
  },
  {
    pattern = {
      'javascript',
      'typescriptreact',
      'typescript',
      'vim',
      'lua',
      'yaml',
      'json',
      'sh',
      'zsh',
      'markdown',
      'wast',
      'graphql',
    },

    command = 'setlocal tabstop=2 softtabstop=2 shiftwidth=2 expandtab smartindent autoindent'
  },
}

for _, indent in pairs(file_indents) do
  vim.api.nvim_create_autocmd('FileType', {
    pattern = indent.pattern,
    command = indent.command,
    group = filetype_indent_group
  })
end

-- grep window
vim.api.nvim_create_autocmd('QuickFixCmdPost', {
  pattern = '*grep*',
  command = 'cwindow',
  group = vim.api.nvim_create_augroup('grepWindow', { clear = true }),
})

-- restore cursorline
vim.api.nvim_create_autocmd('BufReadPost',
  {
    pattern = '*',
    callback = function()
      vim.cmd([[
    if line("'\"") > 0 && line("'\"") <= line("$")
      exe "normal! g'\""
    endif
    ]])
    end,
    group = vim.api.nvim_create_augroup('restoreCursorline', { clear = true })
  })

-- start insert mode when termopen
vim.api.nvim_create_autocmd("TermOpen", {
  pattern = "*",
  callback = function()
    vim.cmd('startinsert')
    vim.cmd('setlocal scrolloff=0')
  end,
  group = vim.api.nvim_create_augroup("neovimTerminal", { clear = true }),
})

-- auto mkdir
local auto_mkdir = function(dir)
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, 'p')
  end
end
vim.api.nvim_create_autocmd('BufWritePre', {
  pattern = '*',
  callback = function()
    auto_mkdir(vim.fn.expand('<afile>:p:h'))
  end,
  group = vim.api.nvim_create_augroup('autoMkdir', { clear = true })
})

-- create zenn article
vim.api.nvim_create_user_command('ZennCreateArticle',
  function(opts)
    local date = vim.fn.strftime('%Y-%m-%d')
    local slug = date .. '-' .. opts.args
    os.execute('npx zenn new:article --emoji 🦍 --slug ' .. slug)
    vim.cmd('edit ' .. string.format('articles/%s.md', slug))
  end, { nargs = 1 })

-- insert markdown link
local insert_markdown_link = function()
  local old = vim.fn.getreg('9')
  local link = vim.fn.trim(vim.fn.getreg())
  if link:match('^http.*') == nil then
    vim.cmd('normal! p')
    return
  end
  vim.cmd('normal! "9y')
  local word = vim.fn.getreg('9')
  local text = string.format('[%s](%s)', word, link)
  vim.fn.setreg('9', text)
  vim.cmd('normal! gv"9p')
  vim.fn.setreg('9', old)
end

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'markdown',
  callback = function()
    map('x', 'p', function()
      insert_markdown_link()
    end, { silent = true, buffer = true })
  end,
  group = vim.api.nvim_create_augroup("markdownInsertLink", { clear = true }),
})

--- syntax clear
-- vim.api.nvim_create_autocmd('FileType', {
--   pattern = {'go', 'vim', 'javascript', 'typescript', 'rust', 'json'},
--   callback = function ()
--     vim.cmd('syntax clear')
--   end
-- })

-- help
vim.api.nvim_create_autocmd("FileType", {
  pattern = "help",
  command = "nnoremap <buffer> <silent>q :bw!<CR>",
  group = vim.api.nvim_create_augroup("helpKeymaps", { clear = true }),
})

-- ############################# lazy config section ###############################
-- lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end

---@diagnostic disable-next-line: undefined-field
vim.opt.rtp:prepend(lazypath)

-- lazy settings
require("lazy").setup({
  -- others
  require('my/plugins/kensaku'),
  require('my/plugins/treesitter'),
  require('my/plugins/skkeleton'),
  require('my/plugins/denops'),
  require('my/plugins/hlchunk'),

  -- window
  require('my/plugins/window/zoom'),
  require('my/plugins/window/winresizer'),
  require('my/plugins/window/winselector'),

  -- completion
  require('my/plugins/completion/nvim-cmp'),
  require('my/plugins/completion/nvim-autopairs'),
  require('my/plugins/completion/sonictemplate'),
  require('my/plugins/completion/emmet'),
  require('my/plugins/completion/copilot'),

  -- filer
  require('my/plugins/filer/fern'),
  require('my/plugins/filer/fern-renderer-nerdfont'),

  -- lsp
  require('my/plugins/lsp/fidget'),
  require('my/plugins/lsp/null-ls'),
  require('my/plugins/lsp/lsp_signature'),
  require('my/plugins/lsp/lsp_lines'),
  require('my/plugins/lsp/mason'),

  -- git
  require('my/plugins/git/gitsigns'),
  require('my/plugins/git/gina'),

  -- languages
  require('my/plugins/lang/rust/crates'),
  require('my/plugins/lang/go/goimports'),

  -- quickfix
  require('my/plugins/quickfix/qfreplace'),
  require('my/plugins/quickfix/bqf'),

  -- statusline
  require('my/plugins/statusline/lualine'),
  require('my/plugins/statusline/bufferline'),

  -- colorscheme
  require('my/plugins/colorscheme/nightfox'),

  -- testing
  require('my/plugins/test/test'),
  require('my/plugins/test/themis'),

  -- infra
  require('my/plugins/infra/k8s'),
  require('my/plugins/infra/docker'),

  -- fuzzifnder
  require('my/plugins/fuzzyfinder/telescope'),
  require('my/plugins/fuzzyfinder/telescope-egrepify'),

  -- documentation
  require('my/plugins/docs/gyazo'),
  require('my/plugins/docs/silicon'),
  require('my/plugins/docs/maketable'),
  require('my/plugins/docs/markdown'),
  require('my/plugins/docs/previm'),
  require('my/plugins/docs/memolist'),
  require('my/plugins/docs/tabular'),
  require('my/plugins/docs/translate'),
  require('my/plugins/docs/vimdoc-ja'),
  require('my/plugins/docs/helpful'),
  require('my/plugins/docs/helpgenerator'),

  -- develop
  require('my/plugins/develop/prettyprint'),
  require('my/plugins/develop/vital'),
  require('my/plugins/develop/vital-whisky'),
  require('my/plugins/develop/capture'),
  require('my/plugins/develop/quickrun'),
  require('my/plugins/develop/graphql'),

  -- othres
  require('my/plugins/utils/guise'),
  require('my/plugins/utils/open-browser'),
  require('my/plugins/utils/dial'),
  require('my/plugins/utils/octo'),
})
