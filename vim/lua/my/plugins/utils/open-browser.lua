local keymaps = require('my/settings/keymaps')
local nmap = keymaps.nmap

local config = function()
  nmap('gop', '<Plug>(openbrowser-open)')
end

local open_browser = {
  'tyru/open-browser-github.vim',
  dependencies = {
    {
      'tyru/open-browser.vim',
      config = config,
    },
  }
}

return open_browser
