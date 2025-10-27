return {
  "skanehira/github-actions.nvim",
  dependencies = {
    'nvim-treesitter/nvim-treesitter',
  },
  config = function()
    local actions = require('github-actions')
    vim.keymap.set('n', '<leader>gd', actions.dispatch_workflow, { desc = 'Dispatch workflow' })
    vim.keymap.set('n', '<leader>gh', actions.show_history, { desc = 'Dispatch workflow' })
    actions.setup({});
  end,
}
