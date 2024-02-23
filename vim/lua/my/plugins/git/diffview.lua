local utils = require('my/utils')
local nmap = utils.keymaps.nmap

local config = function()
  nmap('ms', '<Cmd>DiffviewOpen<CR>')

  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'DiffviewFiles',
    callback = function()
      nmap('q', '<Cmd>tabclose<CR>')
    end,
    group = vim.api.nvim_create_augroup('diffviewInit', { clear = true }),
  })
end

local diffview = {
  'sindrets/diffview.nvim',
  config = config
}

return diffview
