local telescope = {
  "fdschmidt93/telescope-egrepify.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim"
  },
  config = function()
    require("telescope").load_extension("ui-select")
  end
}

return telescope
