local utils = require('my/utils')
local nmap = utils.keymaps.nmap

local winselector = {
  'skanehira/winselector.vim',
  config = function()
    nmap('<C-f>', '<Plug>(winselector)')
  end,
}

return winselector
