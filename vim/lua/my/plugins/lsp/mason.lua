local utils = require('my/utils')
local map = utils.keymaps.map
local nmap = utils.keymaps.nmap

local lsp_on_attach = function(client, bufnr)
  -- Enable completion triggered by <c-x><c-o>
  client.server_capabilities.semanticTokensProvider = nil
  vim.api.nvim_set_option_value('omnifunc', 'v:lua.vim.lsp.omnifunc', {
    buf = bufnr
  })
  local bufopts = { silent = true, buffer = bufnr }
  nmap('K', vim.lsp.buf.hover, bufopts)
  nmap('<Leader>gi', vim.lsp.buf.implementation, bufopts)
  nmap('<Leader>gr', vim.lsp.buf.references, bufopts)
  nmap('<Leader>rn', vim.lsp.buf.rename, bufopts)
  nmap(']d', vim.diagnostic.goto_next, bufopts)
  nmap('[d', vim.diagnostic.goto_prev, bufopts)
  nmap('gO', function()
    vim.lsp.buf_request(0, 'experimental/externalDocs', vim.lsp.util.make_position_params(),
      function(_, url)
        if url then
          vim.fn.jobstart({ 'open', url })
        end
      end)
  end, bufopts)
  nmap('<C-g><C-d>', vim.diagnostic.open_float, bufopts)
  if client.name == 'denols' then
    nmap('<C-]>', vim.lsp.buf.definition, bufopts)
  else
    vim.opt.tagfunc = 'v:lua.vim.lsp.tagfunc'
  end
  map({ 'n', 'x' }, 'ma', vim.lsp.buf.code_action, bufopts)
  nmap('<Leader>gl', vim.lsp.codelens.run, bufopts)

  -- auto format when save the file
  local organize_import = function()
  end
  local actions = vim.tbl_get(client.server_capabilities, 'codeActionProvider', "codeActionKinds")
  if actions ~= nil and vim.tbl_contains(actions, "source.organizeImports") then
    organize_import = function()
      vim.lsp.buf.code_action({ context = { only = { "source.organizeImports" } }, apply = true })
    end
  end
  nmap('mi', organize_import)

  if client.supports_method("textDocument/formatting") then
    nmap(']f', vim.lsp.buf.format, { buffer = bufnr })
  end

  -- local augroup = vim.api.nvim_create_augroup("LspFormatting", { clear = false })
  -- if client.supports_method("textDocument/formatting") then
  --   nmap(']f', vim.lsp.buf.format, { buffer = bufnr })
  --   if client.name == 'sumneko_lua' then
  --     return
  --   end
  --   vim.api.nvim_create_autocmd("BufWritePre", {
  --     callback = function()
  --       organize_import()
  --       vim.lsp.buf.format()
  --     end,
  --     group = augroup,
  --     buffer = bufnr,
  --   })
  -- end
end

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
      }
    }
  })

  -- mason-lspconfig will auto install LS when config included in lspconfig
  local lss = {
    'denols',
    'gopls',
    'rust_analyzer',
    'tsserver',
    'volar',
    'lua_ls',
    'golangci_lint_ls',
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

      opts['on_attach'] = lsp_on_attach

      lspconfig[ls].setup(opts)
    end)()
  end
end

local mason = {
  'williamboman/mason-lspconfig.nvim',
  event = { 'BufReadPre', 'BufNewFile' },
  dependencies = {
    { 'neovim/nvim-lspconfig' },
    {
      'williamboman/mason.nvim',
      config = function() require("mason").setup() end,
    },
  },
  config = config,
}

return mason
