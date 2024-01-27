local keymaps = require('my/keymaps')
local nmap = keymaps.nmap
local vmap = keymaps.vmap

local config = function()
  nmap('gr', '<Plug>(Translate)')
  vmap('gr', '<Plug>(Translate)')
end

local translate = {
  'skanehira/denops-translate.vim',
  config = config
}

return translate
