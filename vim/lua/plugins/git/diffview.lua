local utils = require('utils')
local nmap = utils.keymaps.nmap

local config = function()
  nmap('<C-g>d', '<Cmd>DiffviewOpen<CR>')
  nmap('<C-g>f', '<Cmd>DiffviewFileHistory<CR>')

  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'Diffview*',
    callback = function()
      nmap('q', '<Cmd>tabclose<CR>', { buffer = true })
    end,
    group = vim.api.nvim_create_augroup('diffviewInit', { clear = true }),
  })
end

local diffview = {
  'sindrets/diffview.nvim',
  config = config
}

return diffview
