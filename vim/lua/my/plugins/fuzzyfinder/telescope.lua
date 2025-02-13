local utils = require('my/utils')
local nmap = utils.keymaps.nmap
local open_cmd = utils.get_open_command()

-- telescope.vim
local config = function()
  local telescope = require("telescope")
  local actions = require('telescope.actions')
  local action_state = require("telescope.actions.state")

  local open_file = function(_)
    local selection = action_state.get_selected_entry()
    if selection then
      local filepath = selection.path or selection[1]
      vim.fn.system(open_cmd .. " " .. vim.fn.shellescape(filepath))
    end
  end

  telescope.load_extension("ui-select")
  telescope.setup({
    defaults = {
      mappings = {
        i = {
          ["<C-o>"] = open_file,
        },
        n = {
          ["<C-o>"] = open_file,
        },
      },
    },
    pickers = {
      live_grep = {
        mappings = {
          i = {
            ['<C-o>'] = actions.send_to_qflist + actions.open_qflist,
            ['<C-l>'] = actions.send_to_loclist + actions.open_loclist,
          }
        }
      },
      current_buffer_fuzzy_find = {
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
      },
      egrepify = {
        mappings = {
          i = {
            ['<C-o>'] = actions.send_to_qflist + actions.open_qflist,
            ['<C-l>'] = actions.send_to_loclist + actions.open_loclist,
          }
        }
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

    nmap('<C-p>', builtin('find_files')({ find_command = { 'rg', '--hidden', '--glob', '!.git/', '--files' } }))
    nmap('mr', builtin('resume')())
    nmap('mg', egrepify)
    nmap('md', builtin('diagnostics')())
    nmap('mf', builtin('current_buffer_fuzzy_find')())
    nmap('mh', builtin('help_tags')({ lang = 'ja' }))
    nmap('mo', builtin('oldfiles')())
    nmap('mc', builtin('commands')())
    nmap('<Leader>s', builtin('lsp_document_symbols')())
  end,
  config = config,
}

return telescope
