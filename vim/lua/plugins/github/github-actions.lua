return {
  "skanehira/github-actions.nvim",
  dependencies = {
    'nvim-treesitter/nvim-treesitter',
    'nvim-telescope/telescope.nvim',
  },
  config = function()
    local actions = require('github-actions')
    vim.keymap.set('n', '<leader>gd', actions.dispatch_workflow, { desc = 'Dispatch workflow' })
    vim.keymap.set('n', '<leader>gh', actions.show_history, { desc = 'Show hisotry of workflows' })
    vim.keymap.set('n', '<leader>gw', actions.watch_workflow, { desc = 'Watch workflows' })
    actions.setup({
      actions = {
        enabled = false,
      }
    });
  end,
}
