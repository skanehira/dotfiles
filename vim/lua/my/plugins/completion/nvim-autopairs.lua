local config = function()
  require("nvim-autopairs").setup({ map_c_h = true })
end

local autoparis = {
  'windwp/nvim-autopairs',
  event = { 'InsertEnter' },
  config = config,
}

return autoparis
