return {
  "delphinus/md-render.nvim",
  version = "*",
  dependencies = {
    { "nvim-tree/nvim-web-devicons", version = "*" }, -- optional: file type icons in code blocks
    { "delphinus/budoux.lua",        version = "*" }, -- optional: CJK phrase-level line breaking
  },
  keys = {
    {
      "<leader>mp",
      function()
        vim.opt.signcolumn = 'auto:1'
        require("md-render").preview.auto_toggle({ max_width = vim.o.columns - 1})
      end,
      desc = "Markdown preview (toggle)"
    }
  },
}
