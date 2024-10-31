-- file indent
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
      'nix'
    },
    command = 'setlocal tabstop=2 softtabstop=2 shiftwidth=2 expandtab smartindent autoindent'
  },
}

for _, indent in pairs(file_indents) do
  vim.api.nvim_create_autocmd('FileType', {
    pattern = indent.pattern,
    command = indent.command,
    group = vim.api.nvim_create_augroup('fileTypeIndent', { clear = true })
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
    local utils = require('my/utils')
    utils.keymaps.map('x', 'p', function()
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
