local utils = require('utils')
local nmap = utils.keymaps.nmap

local config = function()
  vim.g['fern#renderer'] = 'nerdfont'
  vim.g['fern#window_selector_use_popup'] = true
  vim.g['fern#default_hidden'] = 1
  vim.g['fern#default_exclude'] = '\\.DS_Store'

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

  local function is_fern_open()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.api.nvim_get_option_value('filetype', { buf = buf }) == 'fern' then
        return true
      end
    end
    return false
  end

  vim.api.nvim_create_autocmd('BufWinEnter', {
    group = vim.api.nvim_create_augroup('fernConfig', { clear = true }),
    nested = true,
    callback = function()
      if vim.bo.filetype ~= "fern" and vim.bo.buftype == "" and is_fern_open() then
        vim.cmd [[Fern . -reveal=% -drawer -stay]]
      end
    end
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
