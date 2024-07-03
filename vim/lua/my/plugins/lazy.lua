local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end

---@diagnostic disable-next-line: undefined-field
vim.opt.rtp:prepend(lazypath)

local plugins = {
  -- etc
  require('my/plugins/etc/kensaku'),
  require('my/plugins/etc/skkeleton'),
  require('my/plugins/etc/denops'),

  -- ui
  require('my/plugins/ui/treesitter'),
  require('my/plugins/ui/hlchunk'),

  -- windows
  require('my/plugins/window/zoom'),
  require('my/plugins/window/winresizer'),
  require('my/plugins/window/winselector'),

  -- completion
  require('my/plugins/completion/nvim-cmp'),
  require('my/plugins/completion/nvim-autopairs'),
  require('my/plugins/completion/sonictemplate'),
  require('my/plugins/completion/emmet'),
  require('my/plugins/completion/copilot'),
  require('my/plugins/completion/copilot-chat'),

  -- filer
  require('my/plugins/filer/fern'),
  require('my/plugins/filer/fern-renderer-nerdfont'),

  -- lsp
  require('my/plugins/lsp/fidget'),
  require('my/plugins/lsp/null-ls'),
  require('my/plugins/lsp/lsp_signature'),
  -- require('my/plugins/lsp/lsp_lines'),
  require('my/plugins/lsp/mason'),

  -- git
  require('my/plugins/git/gitsigns'),
  require('my/plugins/git/gina'),
  require('my/plugins/git/diffview'),

  -- languages
  require('my/plugins/lang/rust/crates'),
  require('my/plugins/lang/go/goimports'),
  require('my/plugins/lang/go/gomodifytags'),

  -- quickfix
  require('my/plugins/quickfix/qfreplace'),
  require('my/plugins/quickfix/bqf'),

  -- statusline
  require('my/plugins/statusline/lualine'),
  require('my/plugins/statusline/bufferline'),

  -- colorscheme
  require('my/plugins/colorscheme/nightfox'),

  -- testing
  require('my/plugins/test/test'),
  require('my/plugins/test/themis'),

  -- infra
  require('my/plugins/infra/k8s'),
  require('my/plugins/infra/docker'),

  -- fuzzifnder
  require('my/plugins/fuzzyfinder/telescope'),
  require('my/plugins/fuzzyfinder/telescope-egrepify'),

  -- documentation
  require('my/plugins/docs/gyazo'),
  require('my/plugins/docs/silicon'),
  require('my/plugins/docs/maketable'),
  require('my/plugins/docs/markdown'),
  require('my/plugins/docs/previm'),
  require('my/plugins/docs/memolist'),
  require('my/plugins/docs/tabular'),
  require('my/plugins/docs/translate'),
  require('my/plugins/docs/vimdoc-ja'),
  require('my/plugins/docs/helpful'),
  require('my/plugins/docs/helpgenerator'),
  require('my/plugins/docs/list2tree'),

  -- develop
  require('my/plugins/develop/prettyprint'),
  require('my/plugins/develop/vital'),
  require('my/plugins/develop/vital-whisky'),
  require('my/plugins/develop/capture'),
  require('my/plugins/develop/quickrun'),
  require('my/plugins/develop/graphql'),
  require('my/plugins/develop/ssr'),
  require('my/plugins/develop/dadbod'),
  require('my/plugins/develop/sqls'),

  -- othres
  require('my/plugins/utils/guise'),
  require('my/plugins/utils/open-browser'),
  require('my/plugins/utils/dial'),
  require('my/plugins/utils/octo'),
}

require("lazy").setup(plugins)
