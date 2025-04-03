local utils = require('my/utils')
local nmap = utils.keymaps.nmap
local vmap = utils.keymaps.vmap

local augment = {
  'augmentcode/augment.vim',
  config = function()
    -- " Send a chat message in normal and visual mode
    nmap('<leader>ac', ':Augment chat<CR>')
    vmap('<leader>ac', ':Augment chat<CR>')

    -- " Start a new chat conversation
    nmap('<leader>an', ':Augment chat-new<CR>')
    vmap('<leader>an', ':Augment chat-new<CR>')

    -- " Toggle the chat panel visibility
    nmap('<leader>at', ':Augment chat-toggle<CR>')
  end
}

return augment
