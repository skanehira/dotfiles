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
      swap = {
        enable = true,
        swap_next = {
          ["<leader>an"] = "@parameter.inner",
        },
        swap_previous = {
          ["<leader>aN"] = "@parameter.inner",
        },
      },
      select = {
        enable = true,
        -- Automatically jump forward to textobj, similar to targets.vim
        lookahead = true,
        keymaps = {
          ["af"] = "@function.outer",
          ["if"] = "@function.inner",
        },
        selection_modes = {
          ['@parameter.outer'] = 'v', -- charwise
          ['@function.outer'] = 'V',  -- linewise
        },
        include_surrounding_whitespace = true,
      },
      move = {
        enable = true,
        set_jumps = true, -- whether to set jumps in the jumplist
        goto_next_start = {
          ["]]"] = "@function.outer",
        },
        goto_previous_start = {
          ["[["] = "@function.outer",
        },
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
