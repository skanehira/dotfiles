local keymaps = require('my/settings/keymaps')
local nmap = keymaps.nmap

local winselector = {
  'skanehira/winselector.vim',
  config = function()
    nmap('<C-f>', '<Plug>(winselector)')
  end,
}

return winselector
