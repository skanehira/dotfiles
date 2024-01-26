local config = function()
  vim.opt.termguicolors = true
  vim.cmd([[
      colorscheme carbonfox
      hi WinSeparator guifg=#535353
      hi Visual ctermfg=159 ctermbg=23 guifg=#b3c3cc guibg=#384851
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
