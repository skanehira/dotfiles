local lsp_signature = {
  'ray-x/lsp_signature.nvim',
  event = { 'BufRead', 'BufNewFile' },
  config = function()
    require('lsp_signature').setup({})
  end
}

return lsp_signature
