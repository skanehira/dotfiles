local keymaps = require('my/keymaps')
local nmap = keymaps.nmap
local xmap = keymaps.xmap

local config = function()
  nmap('gi', '<Plug>(silicon-generate)')
  xmap('gi', '<Plug>(silicon-generate)')
end

local silicon = {
  'skanehira/denops-silicon.vim',
  config = config
}

return silicon
