local keymaps = require('my/settings/keymaps')
local imap = keymaps.imap
local cmap = keymaps.cmap

local skkeleton = {
  'vim-skk/skkeleton',
  init = function()
    vim.api.nvim_create_autocmd('User', {
      pattern = 'skkeleton-initialize-pre',
      callback = function()
        vim.fn['skkeleton#config']({
          globalJisyo = vim.fn.expand('~/.config/skk/SKK-JISYO.L'),
          eggLikeNewline = true,
          keepState = true
        })
      end,
      group = vim.api.nvim_create_augroup('skkelectonInitPre', { clear = true }),
    })
  end,
  config = function()
    imap('<C-j>', '<Plug>(skkeleton-toggle)')
    cmap('<C-j>', '<Plug>(skkeleton-toggle)')
  end
}

return skkeleton
