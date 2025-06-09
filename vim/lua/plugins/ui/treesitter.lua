local config = function()
  ---@diagnostic disable-next-line: missing-fields
  require('nvim-treesitter.configs').setup({
    ensure_installed = {
      'lua',
      'rust',
      'typescript',
      'tsx',
      'go',
      'gomod',
      'sql',
      'toml',
      'yaml',
      'html',
      'javascript',
      'graphql',
      'markdown',
      'markdown_inline',

    },
    auto_install = true,
    highlight = {
      enable = true,
      disable = { 'yaml' },
    }
  })
end

local treesitter = {
  'nvim-treesitter/nvim-treesitter',
  build = ':TSUpdate',
  config = config
}

return treesitter
