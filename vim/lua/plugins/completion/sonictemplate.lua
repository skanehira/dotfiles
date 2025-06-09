local utils = require('utils')
local imap = utils.keymaps.imap

local sonictemplate_config = function()
  imap('<C-g><C-l>', '<plug>(sonictemplate-postfix)')
  vim.g['sonictemplate_author'] = 'skanehira'
  vim.g['sonictemplate_license'] = 'MIT'
  vim.g['sonictemplate_vim_template_dir'] = vim.fn.expand('~/.vim/sonictemplate')
end

local sonictemplate = {
  'mattn/vim-sonictemplate',
  config = sonictemplate_config,
}

return sonictemplate
