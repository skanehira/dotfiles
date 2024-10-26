local config = function()
  require('fidget').setup({
    window = {
      blend = 0,
    },
  })
end

local fidget = {
  'j-hui/fidget.nvim',
  tag = "legacy",
  config = config,
}

return fidget
