local hlchunk = {
  'shellRaining/hlchunk.nvim',
  event = { 'UIEnter' },
  config = function()
    ---@diagnostic disable-next-line: missing-fields
    require('hlchunk').setup({
      ---@diagnostic disable-next-line: missing-fields
      blank = {
        enable = false,
      }
    })
  end
}

return hlchunk
