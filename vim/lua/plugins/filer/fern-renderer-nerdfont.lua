local config = function()
  vim.g['fern#renderer'] = 'nerdfont'
end

local fern_renderer_nerdfont = {
  'lambdalisue/fern-renderer-nerdfont.vim',
  dependencies = {
    'lambdalisue/fern.vim',
    'lambdalisue/nerdfont.vim',
  },
  config = config
}

return fern_renderer_nerdfont
