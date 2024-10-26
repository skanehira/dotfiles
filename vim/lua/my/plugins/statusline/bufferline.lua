local config = function()
  local bufferline = require('bufferline')
  bufferline.setup({
    options = {
      mode = 'tabs',
      diagnostics = 'nvim_lsp',
      ---@diagnostic disable-next-line: unused-local
      diagnostics_indicator = function(count, level, errors, ctx)
        local icon = level:match("error") and " " or " "
        return ' ' .. icon .. count
      end,
      buffer_close_icon = 'x'
    }
  })
end

local bufferline = {
  'akinsho/bufferline.nvim',
  dependencies = 'kyazdani42/nvim-web-devicons',
  config = config
}

return bufferline
