local utils = require('utils')
local nmap = utils.keymaps.nmap

local config = function()
  vim.g['test#javascript#denotest#options'] = { all = '--parallel --unstable -A' }
  vim.g['test#rust#cargotest#options'] = { all = '-- --nocapture' }
  vim.g['test#rust#cargonextest#options'] = { all = '--nocapture' }
  vim.g['test#go#gotest#options'] = { all = '-v -coverprofile=coverage.out' }
  nmap('<Leader>tn', '<Cmd>TestNearest<CR>')
end

local test = {
  'vim-test/vim-test',
  event = 'BufRead',
  config = config,
}

return test
