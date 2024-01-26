local config = function()
  local bufferline = require('bufferline')
  bufferline.setup({
    options = {
      mode = 'tabs',
      hover = {
        enabled = true,
      },
      diagnostics = 'nvim_lsp',
      ---@diagnostic disable-next-line: unused-local
      diagnostics_indicator = function(count, level, errors, ctx)
        -- fix by: https://github.com/akinsho/bufferline.nvim/pull/855
        ---@diagnostic disable-next-line: undefined-field
        local icon = level:match("error") and " " or " "
        return ' ' .. icon .. count
      end,
      indicator = {
        icon = '',
      },
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
