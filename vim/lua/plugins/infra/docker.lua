local utils = require('utils')
local nmap = utils.keymaps.nmap

local docker = {
  'skanehira/denops-docker.vim',
  config = function()
    nmap('gdc', '<Cmd>new | DockerContainers<CR>', {})
    nmap('gdi', '<Cmd>new | DockerImages<CR>', {})
  end
}

return docker
