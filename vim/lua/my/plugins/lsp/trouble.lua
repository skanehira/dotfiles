local trouble = {
  "folke/trouble.nvim",
  cmd = "Trouble",
  keys = {
    {
      "<leader>xx",
      "<cmd>Trouble diagnostics toggle<CR>",
      desc = "Diagnostics (Trouble)",
    },
    {
      "<leader>ic",
      "<cmd>Trouble lsp_incoming_calls<CR>",
    },
    {
      "<Leader>is",
      "<cmd>Trouble lsp_document_symbols win.position=right<CR>",
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
      },
      focus = true,
    })

    -- for transparent background
    vim.cmd([[
      hi TroubleNormal ctermbg=none
      hi TroubleNormalNC ctermbg=none
    ]])
  end
}

return trouble
