local previm = {
  'previm/previm',
  ft = 'markdown',
  init = function()
    vim.g.previm_custom_css_path = vim.fn.stdpath('config') .. '/lua/plugins/docs/previm-custom.css'
  end,
}

return previm
