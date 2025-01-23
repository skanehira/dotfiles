-- create zenn article
vim.api.nvim_create_user_command('ZennCreateArticle',
  function(opts)
    local date = vim.fn.strftime('%Y-%m-%d')
    local slug = date .. '-' .. opts.args
    os.execute('deno run -A  npm:zenn-cli@latest new:article --emoji 🦍 --slug ' .. slug)
    vim.cmd('edit ' .. string.format('articles/%s.md', slug))
  end, { nargs = 1 })
