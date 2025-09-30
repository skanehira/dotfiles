---@type vim.lsp.Config
return {
  workspace_required = true,
  settings = {
    lint = true,
    unstable = true,
    suggest = {
      completeFunctionCalls = true,
      names = true,
      paths = true,
      autoImports = true,
      imports = {
        autoDiscover = true,
        hosts = vim.empty_dict(),
      }
    }
  },
  root_dir = function(bufnr, callback)
    local lspconfig = require("lspconfig")
    local node_root_dir = lspconfig.util.root_pattern("package.json")
    local is_node_repo = node_root_dir(vim.fn.getcwd()) ~= nil

    local found_dirs = vim.fs.find({
      'deno.json',
      'deno.jsonc',
      'deps.ts',
      '.git'
    }, {
      upward = true,
      path = vim.fs.dirname(vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))),
    })
    if not is_node_repo and #found_dirs > 0 then
      return callback(vim.fs.dirname(found_dirs[1]))
    end
  end,
}
