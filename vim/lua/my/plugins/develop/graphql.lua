local keymaps = require('my/settings/keymaps')
local nmap = keymaps.nmap

local config = function()
  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'graphql',
    callback = function()
      nmap('gp', '<Plug>(graphql-execute)')
    end,
    group = vim.api.nvim_create_augroup("graphqlInit", { clear = true }),
  })
end

local graphql = {
  'skanehira/denops-graphql.vim',
  config = config
}

return graphql
