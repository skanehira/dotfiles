---@type vim.lsp.Config
return {
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
