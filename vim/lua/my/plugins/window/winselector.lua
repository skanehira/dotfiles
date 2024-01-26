local keymaps = require('my/keymaps')
local nmap = keymaps.nmap

local winselector = {
  'skanehira/winselector.vim',
  config = function()
    nmap('<C-f>', '<Plug>(winselector)')
  end,
}

return winselector
