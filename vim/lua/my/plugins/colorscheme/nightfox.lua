local config = function()
  vim.opt.termguicolors = true
  vim.cmd([[
      colorscheme carbonfox
      hi DiffAdd guifg=#25be6a
      hi DiffDelete guifg=#ee5396
      ]])

end

local nightfox = {
  'EdenEast/nightfox.nvim',
  lazy = false,
  config = config,
}

return nightfox
