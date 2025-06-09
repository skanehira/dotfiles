---@type vim.lsp.Config
return {
  settings = {
    ["rust-analyzer"] = {
      cargo = {
        features = 'all'
      },
      check = {
        command = "clippy"
      },
      diagnostics = {
        experimental = {
          enable = true,
        }
      }
    }
  }
}
