local config = function()
  vim.api.nvim_create_autocmd("FileType", {
    pattern = {
      'mysql',
      'sql',
    },
    callback = function()
      -- TODO: use sql lsp instead of cmp
      -- require('cmp').setup.buffer({ sources = {{ name = 'vim-dadbod-completion' }} })
    end,
    group = vim.api.nvim_create_augroup("dadbod-ui", { clear = true }),
  })

  vim.api.nvim_create_autocmd('FileType', {
    pattern = { 'dbout' },
    callback = function()
      vim.opt.foldenable = false
    end,
  })
end

return {
  'kristijanhusak/vim-dadbod-ui',
  dependencies = {
    { 'tpope/vim-dadbod', lazy = true },
    -- { 'kristijanhusak/vim-dadbod-completion', ft = { 'sql', 'mysql' }, lazy = true },
  },
  cmd = {
    'DBUI',
    'DBUIToggle',
    'DBUIAddConnection',
    'DBUIFindBuffer',
  },
  init = function()
    vim.g.db_ui_use_nerd_font = 1
  end,
  config = config,
}
