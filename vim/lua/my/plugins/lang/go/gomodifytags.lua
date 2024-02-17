local gomodifytags = {
  'simondrake/gomodifytags',
  ft = 'go',
  config = function()
    local gomodifytags = require('gomodifytags')
    vim.api.nvim_create_user_command('GoAddTags',
      function(opts) gomodifytags.GoAddTags(opts.fargs[1], opts.args) end, { nargs = '+' })
    vim.api.nvim_create_user_command('GoRemoveTags', function(opts)
      gomodifytags.GoRemoveTags(opts.fargs[1], opts.args)
    end, { nargs = '+' })
  end
}

return gomodifytags
