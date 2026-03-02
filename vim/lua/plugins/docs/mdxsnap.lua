return {
  'HidemaruOwO/mdxsnap.nvim',
  cmd = {
    'PasteImage',
  },
  config = function()
    require('mdxsnap').setup({
      DefaultPastePath = 'images'
    })
  end
}
