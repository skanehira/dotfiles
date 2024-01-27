local utils = require('my/utils')
local nmap = utils.keymaps.nmap

local config = function()
  vim.g['fern#renderer'] = 'nerdfont'
  vim.g['fern#window_selector_use_popup'] = true
  vim.g['fern#default_hidden'] = 1
  vim.g['fern#default_exclude'] = '\\.git$\\|\\.DS_Store'

  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'fern',
    callback = function()
      nmap('q', ':q<CR>', { silent = true, buffer = true })
      nmap('<C-x>', '<Plug>(fern-action-open:split)', { silent = true, buffer = true })
      nmap('<C-v>', '<Plug>(fern-action-open:vsplit)', { silent = true, buffer = true })
      nmap('<C-t>', '<Plug>(fern-action-tcd)', { silent = true, buffer = true })
    end,
    group = vim.api.nvim_create_augroup('fernInit', { clear = true }),
  })
end


local fern = {
  'lambdalisue/fern-hijack.vim',
  dependencies = {
    'lambdalisue/fern.vim',
    cmd = 'Fern',
    config = config,
  },
  init = function()
    nmap('<Leader>f', '<Cmd>Fern . -drawer<CR>', { silent = true })
  end
}

return fern
