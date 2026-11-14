-- Neovim プラグインの UI キャプチャ用の最小 init.lua。
-- 使い方: nvim -u /path/to/this-file
-- 置き換える: plugin_root, require(...), open(...), キー操作。
--
-- ポイント:
-- - ユーザーの設定を読み込まない (-u でこのファイルだけを読む)
-- - float などの UI は起動直後のレイアウトが落ち着いてから開く
-- - 選択状態を写したいときは、UI が描画された後にキーを送る
-- - fake gh を使うときは、スクリプトの --path で PATH を渡すか、
--   ここで vim.env.PATH の先頭に足す

local plugin_root = "/absolute/path/to/plugin"
vim.opt.runtimepath:append(plugin_root)

vim.opt.termguicolors = true
vim.opt.laststatus = 2
vim.opt.showtabline = 2
vim.cmd("colorscheme habamax")

-- fake gh を PATH の先頭に置く場合の例:
-- vim.env.PATH = "/tmp/nvim-ui-capture/bin:" .. vim.env.PATH

require("your_plugin").setup({
  -- UI の確認に必要な設定だけを書く
})

-- 対象の UI を開く。project / issue / ファイルなどはプラグインに合わせる。
vim.defer_fn(function()
  require("your_plugin.features.example").open({
    parent_win = vim.api.nvim_get_current_win(),
  })
end, 150)

-- 選択状態やスクロール位置をスクリーンショットに含めたいときに送る。
-- "x" は即時実行。UI のキーマップに合わせて変える。
vim.defer_fn(function()
  vim.api.nvim_feedkeys("lj", "x", false)
end, 1200)
