local utils = require('utils')
local nmap = utils.keymaps.nmap
local xmap = utils.keymaps.xmap

vim.g['silicon_options'] = {
  font = 'Cica',
  no_line_number = true,
  -- background_color = '#434C5E',
  no_window_controls = true,
  theme = 'GitHub',
}

local config = function()
  nmap('gi', '<Plug>(silicon-generate)')
  xmap('gi', '<Plug>(silicon-generate)')
end

local silicon = {
  'skanehira/denops-silicon.vim',
  config = config
}

return silicon
