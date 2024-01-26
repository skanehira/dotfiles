local config = function()
  require('fidget').setup()
end

local fidget = {
  'j-hui/fidget.nvim',
  tag = "legacy",
  config = config,
}

return fidget
