local utils = require('utils')
local nmap = utils.keymaps.nmap
local vmap = utils.keymaps.vmap

local dial = {
  'monaqa/dial.nvim',
  config = function()
    local dial = require("dial.map")
    nmap("<C-a>", dial.inc_normal())
    nmap("<C-x>", dial.dec_normal())
    nmap("g<C-a>", dial.inc_gnormal())
    nmap("g<C-x>", dial.dec_gnormal())
    vmap("<C-a>", dial.inc_visual())
    vmap("<C-x>", dial.dec_visual())
    vmap("g<C-a>", dial.inc_gvisual())
    vmap("g<C-x>", dial.dec_gvisual())
  end
}

return dial
