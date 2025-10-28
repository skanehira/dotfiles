return {
  'lambdalisue/nvim-aibo',
  config = function()
    require('aibo').setup({
      prompt = {
        on_attach = function(bufnr)
          local opts = { buffer = bufnr, nowait = true, silent = true }
          vim.keymap.set({ 'n', 'i' }, '<C-c>', '<Plug>(aibo-send)<Esc>', opts)
          vim.keymap.set({ 'n', 'i' }, '<C-d>', '<Plug>(aibo-send)<C-d>', opts)
        end,
      },
      tools = {
        claude = {
          on_attach = function(bufnr)
            local win_id = vim.fn.win_findbuf(bufnr)[0]
            local opts = { buffer = bufnr, nowait = true, silent = true }
            vim.api.nvim_set_option_value('winfixwidth', true, { win = win_id })
            vim.keymap.set('n', 'qq', '<Cmd>bw!<CR>', opts)
            vim.keymap.set('n', '<C-u>', '<PageUp>', opts)
          end
        }
      }
    })

    vim.api.nvim_create_user_command('Claude', function(opts)
      local width = math.floor(vim.o.columns * 2 / 6)
      vim.cmd(string.format('Aibo -toggle -opener="botright %dvsplit" claude %s', width, opts.args))
    end, { nargs = '*' })

    vim.keymap.set('n', '<leader>ac', '<Cmd>Claude<CR>')
    vim.keymap.set('n', '<leader>ar', '<Cmd>Claude -r<CR>')
    vim.keymap.set('n', '<leader>aC', '<Cmd>Claude -c<CR>')
  end
}
