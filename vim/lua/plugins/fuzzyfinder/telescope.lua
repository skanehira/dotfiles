local utils = require('utils')
local nmap = utils.keymaps.nmap
local open_cmd = utils.get_open_command()

-- telescope.vim
local config = function()
  local telescope = require("telescope")
  local actions = require('telescope.actions')
  local action_state = require("telescope.actions.state")
  local lga_actions = require("telescope-live-grep-args.actions")

  local open_file = function(_)
    local selection = action_state.get_selected_entry()
    if selection then
      local filepath = selection.path or selection[1]
      vim.fn.system(open_cmd .. " " .. vim.fn.shellescape(filepath))
    end
  end

  telescope.setup({
    defaults = {
      vimgrep_arguments = {
        'rg',
        '--color=never',
        '--no-heading',
        '--with-filename',
        '--line-number',
        '--column',
        '--smart-case',
        '--hidden',
        '--glob',
        '!.git/'
      },
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
      live_grep_args = {
        mappings = {
          i = {
            ['<C-f>'] = function()
              vim.fn.feedkeys(vim.api.nvim_replace_termcodes('<Right>', true, false, true), 'i')
            end,
            ["<C-k>"] = lga_actions.quote_prompt(),
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
    { 'nvim-telescope/telescope-live-grep-args.nvim' },
  },
  init = function()
    local function builtin(name)
      return function(opt)
        return function()
          return require('telescope.builtin')[name](opt or {})
        end
      end
    end

    local function live_grep_args()
      require('telescope').extensions.live_grep_args.live_grep_args({})
    end

    nmap('<C-p>', builtin('find_files')({ find_command = { 'rg', '--hidden', '--glob', '!.git/', '--files' } }))
    nmap('mr', builtin('resume')())
    nmap('mg', live_grep_args)
    nmap('md', builtin('diagnostics')())
    nmap('mf', builtin('current_buffer_fuzzy_find')())
    nmap('mh', builtin('help_tags')({ lang = 'ja' }))
    nmap('mo', builtin('oldfiles')())
    nmap('mc', builtin('commands')())
    nmap('mb', builtin('buffers')())
    nmap('<Leader>s', builtin('lsp_document_symbols')())
  end,
  config = config,
}

return telescope
