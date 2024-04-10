local utils = require('my/plugins/lsp/utils')

local config = function()
  require('lspconfig').sqls.setup({
    on_attach = function(client, bufnr)
      require('sqls').on_attach(client, bufnr)
      utils.lsp_on_attach(client, bufnr)
    end,
    cmd = { 'sqls', '--config', '~/.config/sqls/config.yaml' },
    filetypes = { 'sql', 'mysql' },
  })
end

local slqs = {
  'nanotee/sqls.nvim',
  config = config,
  dependencies = {
    { 'neovim/nvim-lspconfig' },
  }
}

return slqs
