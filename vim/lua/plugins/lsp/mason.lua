local utils = require('utils')
local nmap = utils.keymaps.nmap

local signs = { Error = " ", Warn = " ", Hint = "💡", Info = " " }
for type, icon in pairs(signs) do
  local hl = "DiagnosticSign" .. type
  vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = hl })
end

---@param client vim.lsp.Client
local lsp_on_attach = function(client, bufnr)
  -- disable lsp highlight
  client.server_capabilities.semanticTokensProvider = nil
  -- Enable completion triggered by <c-x><c-o>
  vim.api.nvim_set_option_value('omnifunc', 'v:lua.vim.lsp.omnifunc', {
    buf = bufnr
  })
  local bufopts = { silent = true, buffer = bufnr }
  nmap('K', vim.lsp.buf.hover, bufopts)
  nmap('<Leader>gi', vim.lsp.buf.implementation, bufopts)
  nmap('<Leader>gr', vim.lsp.buf.references, bufopts)
  nmap('<Leader>rn', vim.lsp.buf.rename, bufopts)
  nmap(']d', function() vim.diagnostic.jump({ count = 1 }) end, bufopts)
  nmap('[d', function() vim.diagnostic.jump({ count = -1 }) end, bufopts)
  nmap('gO', function()
    ---@diagnostic disable-next-line: param-type-mismatch
    vim.lsp.buf_request(0, 'experimental/externalDocs', vim.lsp.util.make_position_params(0, client.offset_encoding),
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
  -- map({ 'n', 'x' }, 'ma', vim.lsp.buf.code_action, bufopts)
  nmap('<Leader>gl', vim.lsp.codelens.run, bufopts)

  -- auto format when save the file
  local organize_import = function()
  end
  local actions = vim.tbl_get(client.server_capabilities, 'codeActionProvider', "codeActionKinds")
  if actions ~= nil and vim.tbl_contains(actions, "source.organizeImports") then
    organize_import = function()
      vim.lsp.buf.code_action({ context = { only = { "source.organizeImports" }, diagnostics = {} }, apply = true })
    end
  end
  nmap('mi', organize_import)
  nmap(']f', vim.lsp.buf.format, { buffer = bufnr })

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

vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('lsp', { clear = true }),
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if client then
      -- Enable marksman only for physical files
      if client.name == 'marksman' then
        local bufname = vim.api.nvim_buf_get_name(args.buf)
        -- Exclude virtual buffers (e.g., claudecode://prompt)
        if bufname == '' or bufname:match('^%w+://') then
          return
        end
      end
      lsp_on_attach(client, args.buf)
    end
  end,
})

local config = function()
  require('mason-lspconfig').setup({
    automatic_enable = true,
    ensure_installed = {
      'ts_ls',
      'vue_ls',
      'lua_ls',
      'eslint',
      'graphql',
      'bashls',
      'yamlls',
      'jsonls',
      'vimls',
      'marksman',
      'taplo',
      'clangd',
      'terraformls',
      'biome',
      'tsp_server',
      'zls',
      'regols',
      'gopls',
      -- 'nil_ls'
    }
  })

  local lsp_names = {
    'rust_analyzer',
    'denols',
  }
  vim.lsp.enable(lsp_names)
end

local mason = {
  'williamboman/mason-lspconfig.nvim',
  event = { 'BufReadPre', 'BufNewFile', 'BufEnter', 'BufNew' },
  dependencies = {
    {
      'mason-org/mason.nvim',
      dependencies = {
        { 'neovim/nvim-lspconfig' },
      },
      config = function()
        require("mason").setup()
      end,
    },
  },
  config = config,
}

return mason
