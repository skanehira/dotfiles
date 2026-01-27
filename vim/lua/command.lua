-- create zenn article
vim.api.nvim_create_user_command('ZennCreateArticle',
  function(opts)
    local date = vim.fn.strftime('%Y-%m-%d')
    local slug = date .. '-' .. opts.args
    os.execute('deno run -A  npm:zenn-cli@latest new:article --emoji 🦍 --slug ' .. slug)
    vim.cmd('edit ' .. string.format('articles/%s.md', slug))
  end, { nargs = 1 })

vim.api.nvim_create_user_command("TerminalExec", function(opts)
  local cmd = opts.args
  vim.cmd("botright 20new")
  local buf = vim.api.nvim_get_current_buf()
  vim.fn.jobstart(
    { "zsh", "-i", "-c", cmd },
    {
      stdout_buffered = true,
      stderr_buffered = true,
      pty = true,
      term = true,
      on_exit = function(_, code, _)
        if code == 0 then
          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(buf) then
              vim.api.nvim_buf_delete(buf, { force = true })
            end
          end)
        end
      end,
    }
  )
end, { nargs = "+", complete = "shellcmd" })

vim.api.nvim_create_user_command("Ghost", function(opts)
  local cmd = "ghost"
  if opts.args ~= "" then
    cmd = cmd .. " " .. opts.args
  end
  vim.cmd("TerminalExec " .. cmd)
end, { nargs = "*" })
