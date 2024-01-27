local keymaps = require('my/settings/keymaps')
local nmap = keymaps.nmap
local vmap = keymaps.vmap

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
