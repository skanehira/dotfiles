local utils = require('my/utils')
local imap = utils.keymaps.imap

local config = function()
  vim.g['copilot_no_tab_map'] = 1
  imap('<Plug>(vimrc:copilot-dummy-map)', 'copilot#Accept("\\<Tab>")', { expr = true })
end

local copilot = {
  'github/copilot.vim',
  event = { 'BufRead', 'BufNewFile' },
  config = config
}

return copilot
