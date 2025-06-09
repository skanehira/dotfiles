local crates = {
  'Saecki/crates.nvim',
  dependencies = {
    { 'nvim-lua/plenary.nvim' },
  },
  config = function()
    require('crates').setup({})
  end
}

return crates
