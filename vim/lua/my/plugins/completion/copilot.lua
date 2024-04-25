local utils = require('my/utils')
local imap = utils.keymaps.imap

local config = function()
  vim.g['copilot_no_tab_map'] = 1
  imap('<Plug>(vimrc:copilot-dummy-map)', 'copilot#Accept("\\<Tab>")', { expr = true })
  vim.g['copilot_filetypes'] = {
    ['*'] = false,
    rust = true,
    go = true,
    typescript = true,
    javascript = true,
    javascriptreact = true,
    typescriptreact = true,
    yaml = true,
    json = true,
    toml = true,
    css = true,
    vim = true,
    lua = true,
    help = true,
    python = true,
    sh = true,
    fish = true,
    dockerfile = true,
    make = true,
    c = true,
    java = true,
    sql = true,
    graphql = true,
    graphqls = true,
    graphqlschema = true,
    tmux = true,
    vue = true,
    gitconfig = true,
    gitignore = true,
    gitcommit = true,
    gitrebase = true,
    gitmerge = true,
    ['gina-commit'] = true,
    terraform = true,
    hcl = true,
    wat = true,
  }
end

local copilot = {
  'github/copilot.vim',
  event = { 'BufRead', 'BufNewFile' },
  config = config
}

return copilot
