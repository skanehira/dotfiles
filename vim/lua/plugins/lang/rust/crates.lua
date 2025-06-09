local crates = {
  'Saecki/crates.nvim',
  dependencies = {
    { 'nvim-lua/plenary.nvim' },
  },
  config = function()
    require('crates').setup({
      null_ls = {
        enabled = true,
        name = "crates.nvim",
      },
    })
  end
}

return crates
