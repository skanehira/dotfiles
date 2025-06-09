local utils = require('utils')
local nmap = utils.keymaps.nmap

return {
  "andythigpen/nvim-coverage",
  version = "*",
  config = function()
    local cov = require("coverage")
    cov.setup({
      auto_reload = true,
    })

    nmap('<Leader>cs', function ()
      cov.load(true)
      cov.summary()
    end)
  end,
}
