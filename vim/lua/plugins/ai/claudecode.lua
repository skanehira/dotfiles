return {
  "coder/claudecode.nvim",
  cmd = {
    'ClaudeCode',
  },
  keys = {
    { "<leader>ac", "<cmd>ClaudeCode<cr>",            desc = "Toggle Claude" },
    { "<leader>af", "<cmd>ClaudeCodeFocus<cr>",       desc = "Focus Claude" },
    { "<leader>ar", "<cmd>ClaudeCode --resume<cr>",   desc = "Resume Claude" },
    { "<leader>aC", "<cmd>ClaudeCode --continue<cr>", desc = "Continue Claude" },
    { "<leader>as", "<cmd>ClaudeCodeSend<cr>",        mode = "v",              desc = "Send to Claude" },
    { "<leader>an", ":new claudecode://prompt<CR>",   desc = "Continue Claude" },
  },
  config = function()
    require("claudecode").setup()

    vim.api.nvim_create_autocmd({ "BufReadCmd" }, {
      pattern = { "claudecode://prompt" },
      callback = function()
        local bufnr = vim.api.nvim_get_current_buf()
        vim.api.nvim_set_option_value('filetype', 'markdown', { buf = bufnr })
        vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = bufnr })
        vim.api.nvim_set_option_value('buflisted', false, { buf = bufnr })
        vim.api.nvim_buf_set_keymap(bufnr, 'n', 'q', '<Cmd>q!<CR>', { noremap = true, silent = true })

        vim.cmd('startinsert')

        vim.keymap.set('n', '<CR>', function()
          local claude_terminal_bufnr = require("claudecode.terminal").get_active_terminal_bufnr()
          if not claude_terminal_bufnr then
            return
          end
          local terminal_job_id = vim.fn.getbufvar(claude_terminal_bufnr, 'terminal_job_id')
          if not terminal_job_id then
            return
          end
          local current_win = vim.api.nvim_get_current_win()
          local prompt = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
          vim.fn.chansend(terminal_job_id, prompt)
          vim.cmd('ClaudeCodeFocus')
          vim.defer_fn(function()
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
            vim.defer_fn(function()
              vim.api.nvim_set_current_win(current_win)
              vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
              vim.cmd('startinsert')
            end, 100)
          end, 100)
        end, { noremap = true, silent = true, buffer = true })
      end,
    })
  end
}
