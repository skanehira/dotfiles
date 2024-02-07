local utils = require('my/utils')
local map = utils.keymaps.map

local config = function()
  local ssr = require("ssr")
  map({ "n", "x" }, "<leader>sr", ssr.open)
end

local ssr = {
  'cshuaimin/ssr.nvim',
  config = config
}

return ssr
