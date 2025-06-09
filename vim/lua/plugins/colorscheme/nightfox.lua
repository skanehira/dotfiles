local config = function()
  require('nightfox').setup({
    options = {
      transparent = true,
    }
  })
  vim.opt.termguicolors = true
  vim.cmd([[
      colorscheme carbonfox
      hi WinSeparator guifg=#535353
      hi Visual ctermfg=159 ctermbg=23 guifg=#b3c3cc guibg=#384851
      hi DiffAdd guifg=#25be6a
      hi DiffDelete guifg=#ee5396

      hi TabLine ctermbg=none guibg=none
      hi TabLineFill ctermbg=none guibg=none
      ]])
end

local nightfox = {
  'EdenEast/nightfox.nvim',
  lazy = false,
  config = config,
}

return nightfox
