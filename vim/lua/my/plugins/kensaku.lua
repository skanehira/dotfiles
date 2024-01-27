local keymaps = require('my/settings/keymaps')
local cmap = keymaps.cmap

local kensaku_search = {
  'lambdalisue/kensaku-search.vim',
  dependencies = {
    'lambdalisue/kensaku.vim',
  },
  config = function()
    cmap('<CR>', '<Plug>(kensaku-search-replace)<CR>', {})
  end
}

return kensaku_search
