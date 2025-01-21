local trouble = {
  "folke/trouble.nvim",
  cmd = "Trouble",
  keys = {
    {
      "<leader>xx",
      "<cmd>Trouble diagnostics toggle<cr>",
      desc = "Diagnostics (Trouble)",
    },
    {
      "<leader>ic",
      "<cmd>Trouble lsp_incoming_calls<cr>",
    },
    {
      "<Leader>is",
      "<cmd>Trouble symbols toggle<cr>",
    }
  },
  config = function()
    require('trouble').setup({
      auto_close = true,
      win = {
        size = {
          width = 60,
          height = 10,
        }
      }
    })

    -- for transparent background
    vim.cmd([[
      hi TroubleNormal ctermbg=none
      hi TroubleNormalNC ctermbg=none
    ]])
  end
}

return trouble
