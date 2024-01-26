local config = function()
  require('lualine').setup({
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
