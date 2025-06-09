vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(
  vim.lsp.handlers.hover, {
    border = "single"
  })
-- use tiny-inline-diagnostic instead of virtual text
vim.diagnostic.config({ virtual_text = false })
