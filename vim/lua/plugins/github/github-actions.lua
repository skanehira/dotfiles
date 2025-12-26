return {
  "skanehira/github-actions.nvim",
  dependencies = {
    'nvim-treesitter/nvim-treesitter',
    'nvim-telescope/telescope.nvim',
  },
  config = function()
    local actions = require('github-actions')
    vim.keymap.set('n', '<leader>gad', actions.dispatch_workflow, { desc = 'Dispatch workflow' })
    vim.keymap.set('n', '<leader>gah', actions.show_history, { desc = 'Show hisotry of workflows' })
    vim.keymap.set('n', '<leader>gaw', actions.watch_workflow, { desc = 'Watch workflows' })
    vim.keymap.set('n', '<leader>gap', function()
      actions.show_history({ pr_mode = true })
    end, { desc = 'Watch workflows' })
    actions.setup({
      actions = {
        enabled = false,
      }
    });
  end,
}
