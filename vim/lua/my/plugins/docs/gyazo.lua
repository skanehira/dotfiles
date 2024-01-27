local keymaps = require('my/keymaps')
local nmap = keymaps.nmap

vim.g['gyazo_insert_markdown'] = true

local config = function()
  nmap('gup', '<Plug>(gyazo-upload)')
end

local gyazo = {
  'skanehira/gyazo.vim',
  config = config,
  ft = 'markdown',
}

return gyazo
