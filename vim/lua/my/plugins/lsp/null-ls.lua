local null_ls = {
  'jose-elias-alvarez/null-ls.nvim',
  event = { 'BufRead', 'BufNewFile' },
  dependencies = {
    { 'nvim-lua/plenary.nvim' },
  },
  config = function()
    local null_ls = require('null-ls')
    null_ls.setup({
      sources = {
        null_ls.builtins.formatting.prettier.with {
          prefer_local = 'node_modules/.bin',
          condition = function(utils)
            -- https://prettier.io/docs/en/configuration.html
            return utils.root_has_file {
              '.prettierrc',
              '.prettierrc.js',
              '.prettierrc.cjs',
              '.prettierrc.json',
              '.prettierrc.yml',
              '.prettierrc.yaml',
              'prettier.config.js',
              'prettier.config.cjs',
            }
          end,
        },
        null_ls.builtins.diagnostics.actionlint,
        null_ls.builtins.diagnostics.textlint.with {
          prefer_local = 'node_modules/.bin',
          condition = function(utils)
            return utils.root_has_file {
              '.textlintrc',
              '.textlintrc.js',
              '.textlintrc.json',
              '.textlintrc.yml',
              '.textlintrc.yaml',
            }
          end,
        },
      }
    })
  end
}

return null_ls
