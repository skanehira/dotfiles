local keymaps = require('my/keymaps')
local nmap = keymaps.nmap

local docker = {
  'skanehira/denops-docker.vim',
  config = function()
    nmap('gdc', '<Cmd>new | DockerContainers<CR>', {})
    nmap('gdi', '<Cmd>new | DockerImages<CR>', {})
  end
}

return docker
