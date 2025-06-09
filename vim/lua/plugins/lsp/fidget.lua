local config = function()
  require('fidget').setup({
    notification = {
      window = {
        winblend = 0,
      },
    }
  })
end

local fidget = {
  'j-hui/fidget.nvim',
  config = config,
}

return fidget
