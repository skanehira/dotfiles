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

return {
  lsp_on_attach = lsp_on_attach
}
