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
      "<cmd>Trouble symbols<CR>",
    }
  },
  config = function()
    require('trouble').setup({
      multiline = false,
      auto_close = true,
      win = {
        size = {
          width = 60,
          height = 10,
        }
      },
      focus = true,
      modes = {
        symbols = {
          desc = "document symbols",
          mode = "lsp_document_symbols",
          focus = true,
          win = { position = "right" },
          filter = {
            any = {
              kind = {
                "Class",
                "Constant",
                "Constructor",
                "Enum",
                "EnumMember",
                "Field",
                "Function",
                "Interface",
                "Method",
                "Module",
                "Namespace",
                "Package",
                "Property",
                "Struct",
                "Trait",
                "Object",
                "TypeParameter"
              },
            },
          },
        },
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
