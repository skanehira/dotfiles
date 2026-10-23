---@type vim.lsp.Config
return {
  workspace_required = true,
  -- lspconfig 同梱のデフォルトは deno.json / deno.lock が無いと .git や cwd に
  -- フォールバックして必ず attach するため、deno.json を置かないリポジトリの
  -- deno スクリプトに denols と二重で付く。node プロジェクトに限定する
  root_dir = function(bufnr, on_dir)
    local root = vim.fs.root(bufnr, { 'package.json' })
    if root then
      on_dir(root)
    end
  end,
}
