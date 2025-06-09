local utils = require('utils')
local nmap = utils.keymaps.nmap
local vmap = utils.keymaps.vmap

local config = function()
  nmap('gr', '<Plug>(Translate)')
  vmap('gr', '<Plug>(Translate)')
end

local translate = {
  'skanehira/denops-translate.vim',
  config = config
}

return translate
