local config = function()
  local custom = require('lualine.themes.nightfox')

  require('lualine').setup({
    options = {
      section_separators = { left = '', right = '' },
      theme = custom,
    },
    sections = {
      lualine_c = {
        {
          'filename',
          path = 3,
        }
      }
    }
  })
end

local lualine = {
  'nvim-lualine/lualine.nvim',
  dependencies = 'kyazdani42/nvim-web-devicons',
  config = config,
}

return lualine
