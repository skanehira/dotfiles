local utils = require('my/utils')
local nmap = utils.keymaps.nmap

-- telescope.vim
local config = function()
  local telescope = require("telescope")
  local actions = require('telescope.actions')

  telescope.load_extension("ui-select")
  telescope.setup({
    pickers = {
      live_grep = {
        mappings = {
          i = {
            ['<C-o>'] = actions.send_to_qflist + actions.open_qflist,
            ['<C-l>'] = actions.send_to_loclist + actions.open_loclist,
          }
        }
      }
    },
    extensions = {
      ['ui-select'] = {
        require('telescope.themes').get_dropdown({})
      }
    }
  })
end

local telescope = {
  'nvim-telescope/telescope.nvim',
  dependencies = {
    { 'nvim-lua/plenary.nvim' },
    { 'nvim-telescope/telescope-ui-select.nvim' },
  },
  init = function()
    local function builtin(name)
      return function(opt)
        return function()
          return require('telescope.builtin')[name](opt or {})
        end
      end
    end

    local function egrepify()
      require('telescope').extensions.egrepify.egrepify({})
    end

    nmap('<C-p>', builtin('find_files')())
    nmap('mg', egrepify)
    nmap('md', builtin('diagnostics')())
    nmap('mf', builtin('current_buffer_fuzzy_find')())
    nmap('mh', builtin('help_tags')({ lang = 'ja' }))
    nmap('mo', builtin('oldfiles')())
    nmap('ms', builtin('git_status')())
    nmap('mc', builtin('commands')())
    nmap('<Leader>s', builtin('lsp_document_symbols')())
  end,
  config = config,
}

return telescope
