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
    },
    textobjects = {
      select = {
        enable = true,

        -- Automatically jump forward to textobj, similar to targets.vim
        lookahead = true,

        keymaps = {
          ["af"] = "@function.outer",
          ["if"] = "@function.inner",
        },
        -- You can choose the select mode (default is charwise 'v')
        --
        -- Can also be a function which gets passed a table with the keys
        -- * query_string: eg '@function.inner'
        -- * method: eg 'v' or 'o'
        -- and should return the mode ('v', 'V', or '<c-v>') or a table
        -- mapping query_strings to modes.
        selection_modes = {
          ['@parameter.outer'] = 'v', -- charwise
          ['@function.outer'] = 'V',  -- linewise
        },
        include_surrounding_whitespace = true,
      },
    },
  })
end

local treesitter = {
  'nvim-treesitter/nvim-treesitter',
  build = ':TSUpdate',
  dependencies = {
    'nvim-treesitter/nvim-treesitter-textobjects',
  },
  config = config
}

return treesitter
