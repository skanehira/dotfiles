local utils = require('utils')
local nmap = utils.keymaps.nmap

local signs = { Error = " ", Warn = " ", Hint = "💡", Info = " " }
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

-- 全 LSP server を有効化。binary は Nix で /nix/store/... に提供済
-- (nix/modules/home/packages.nix の lspServers セクション)。Mason は廃止。
local servers = {
  -- nixpkgs 由来
  'ts_ls', 'vue_ls', 'lua_ls', 'eslint', 'jsonls', 'graphql',
  'bashls', 'yamlls', 'vimls', 'marksman', 'taplo', 'clangd',
  'terraformls', 'biome', 'oxlint', 'zls', 'regols', 'gopls',
  'buf_ls', 'rust_analyzer', 'denols',
  -- 自前 derivation (nix/pkgs/) / flake input (skanehira/version-lsp)
  'tsp_server', 'gh_actions_ls', 'version_ls',
}

return {
  'neovim/nvim-lspconfig',
  event = { 'BufReadPre', 'BufNewFile', 'BufEnter', 'BufNew' },
  config = function()
    vim.lsp.enable(servers)
  end,
}
