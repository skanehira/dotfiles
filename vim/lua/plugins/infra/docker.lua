local utils = require('utils')
local nmap = utils.keymaps.nmap

local docker = {
  'skanehira/docker.nvim',
  config = function()
    nmap('gdc', '<Cmd>Docker containers<CR>', {})
    nmap('gdi', '<Cmd>Docker images<CR>', {})
    nmap('gdv', '<Cmd>Docker volumes<CR>', {})
  end
}

return docker
