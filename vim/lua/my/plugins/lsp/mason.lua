local utils = require('my/plugins/lsp/utils')

local config = function()
  local signs = { Error = " ", Warn = " ", Hint = "💡", Info = " " }
  for type, icon in pairs(signs) do
    local hl = "DiagnosticSign" .. type
    vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = hl })
  end

  require('mason-lspconfig').setup({
    automatic_installation = {
      exclude = {
        'gopls',
        'denols',
        'rust_analyzer',
        'nil_ls',
      }
    }
  })

  -- mason-lspconfig will auto install LS when config included in lspconfig
  local lss = {
    'denols',
    'gopls',
    'rust_analyzer',
    'ts_ls',
    'volar',
    'lua_ls',
    --'golangci_lint_ls',
    'eslint',
    'graphql',
    'bashls',
    'yamlls',
    'jsonls',
    'vimls',
    'marksman',
    'taplo',
    -- need manual install
    -- https://github.com/kitagry/regols
    'regols',
    'clangd',
    'terraformls',
    -- https://github.com/oxalica/nil
    'nil_ls'
  }

  local lspconfig = require("lspconfig")
  local node_root_dir = lspconfig.util.root_pattern("package.json")
  local is_node_repo = node_root_dir(vim.fn.getcwd()) ~= nil

  for _, ls in pairs(lss) do
    (function()
      local opts = {}

      if ls == 'denols' then
        -- dont start LS in nodejs repository
        if is_node_repo then
          return
        end
        opts = {
          cmd = { 'deno', 'lsp' },
          root_dir = lspconfig.util.root_pattern('deps.ts', 'deno.json', 'import_map.json', '.git'),
          settings = {
            deno = {
              lint = true,
              unstable = true,
              suggest = {
                imports = {
                  hosts = {
                    ["https://deno.land"] = true,
                    ["https://cdn.nest.land"] = true,
                    ["https://crux.land"] = true,
                  },
                },
              },
            }
          },
        }
      elseif ls == 'tsserver' then
        if not is_node_repo then
          return
        end

        opts = {
          root_dir = lspconfig.util.root_pattern('package.json', 'node_modules'),
        }
      elseif ls == 'regols' then
        opts = {
          cmd = { 'regols' },
          filetypes = { 'rego' },
          root_dir = lspconfig.util.root_pattern('.git')
        }
      elseif ls == 'lua_ls' then
        opts = {
          settings = {
            Lua = {
              runtime = {
                version = 'LuaJIT',
              },
              diagnostics = {
                -- Get the language server to recognize the `vim` global
                globals = { 'vim' },
              },
              workspace = {
                library = vim.list_extend(vim.api.nvim_get_runtime_file('lua', true), {
                  vim.fs.joinpath(vim.fn.stdpath('config') --[[@as string]], 'lua'),
                  vim.fs.joinpath(vim.env.VIMRUNTIME, "lua"),
                  '${3rd}/luv/library',
                  '${3rd}/busted/library',
                  '${3rd}/luassert/library',
                }),
              },
            },
          },
        }
      elseif ls == 'yamlls' then
        opts = {
          settings = {
            yaml = {
              schemas = {
                ['https://json.schemastore.org/github-workflow.json'] = "/.github/workflows/*",
                ['https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json'] =
                "*compose.y*ml"
              }
            }
          }
        }
      elseif ls == "rust_analyzer" then
        opts = {
          settings = {
            ["rust-analyzer"] = {
              cargo = {
                features = 'all'
              },
              check = {
                command = "clippy"
              },
              diagnostics = {
                experimental = {
                  enable = true,
                }
              }
            }
          }
        }
      end

      opts['on_attach'] = utils.lsp_on_attach

      lspconfig[ls].setup(opts)
    end)()
  end
end

local mason = {
  'williamboman/mason-lspconfig.nvim',
  event = { 'BufReadPre', 'BufNewFile', 'BufEnter', 'BufNew' },
  dependencies = {
    { 'neovim/nvim-lspconfig' },
    {
      'williamboman/mason.nvim',
      config = function()
        require("mason").setup()
        require('mason-lspconfig').setup()
      end,
    },
  },
  config = config,
}

return mason
