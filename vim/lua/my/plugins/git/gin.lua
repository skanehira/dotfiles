local utils = require('my/utils')
local vmap = utils.keymaps.vmap
local nmap = utils.keymaps.nmap

local config = function()
  nmap('gs', '<Cmd>GinStatus ++opener=new<CR>')
  nmap('gb', '<Cmd>GinBranch ++opener=new<CR>')
  nmap('gu', '<Cmd>GinBrowse ++yank -n --permalink<CR>')
  vmap('gu', ':GinBrowse ++yank -n --permalink<CR>')

  -- status keymaps
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "gin-status",
    callback = function()
      local nkeymaps = {
        { lhs = 'gp', rhs = '<Cmd>Gin push<CR>' },
        { lhs = 'gr', rhs = '<Cmd>terminal gh pr create<CR>' },
        { lhs = 'gl', rhs = '<Cmd>Gin pull<CR>' },
        { lhs = 'cm', rhs = ':Gin commit<CR>' },
        { lhs = 'ca', rhs = ':Gin commit --amend<CR>' },
        { lhs = 'q',  rhs = '<Cmd>bw<CR>' },
      }

      for _, m in pairs(nkeymaps) do
        nmap(m.lhs, m.rhs, { buffer = true })
      end
    end,
    group = vim.api.nvim_create_augroup("gin-status-keymaps", { clear = true }),
  })

  -- branch keymaps
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "gin-branch",
    callback = function()
      local nkeymaps = {
        { lhs = 'n', rhs = '<Plug>(gin-action-new)' },
        { lhs = 'd', rhs = '<Plug>(gin-action-delete)' },
        { lhs = 'D', rhs = '<Plug>(gin-action-delete:force)' },
      }

      for _, m in pairs(nkeymaps) do
        nmap(m.lhs, m.rhs, { buffer = true })
      end
    end,
    group = vim.api.nvim_create_augroup("gin-branch-keymaps", { clear = true }),
  })

  -- ref: https://blog.atusy.net/2024/03/15/instant-fixup-with-gin-vim/
  vim.api.nvim_create_autocmd("BufReadCmd", {
    group = vim.api.nvim_create_augroup("gin-custom", {}),
    pattern = "gin*://*",
    callback = function(ctx)
      nmap("a", function()
        require("telescope.builtin").keymaps({ default_text = "gin-action " })
      end, { buffer = ctx.buf })
      nmap('q', '<Cmd>bw<CR>', { buffer = ctx.buf })
    end,
  })
end

return {
  'lambdalisue/vim-gin',
  config = config,
}
