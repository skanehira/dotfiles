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
  tag = 'v1.6.1', -- waiting fix by https://github.com/j-hui/fidget.nvim/issues/288
  config = config,
}

return fidget
