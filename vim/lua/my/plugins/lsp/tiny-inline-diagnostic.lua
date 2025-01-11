return {
  "rachartier/tiny-inline-diagnostic.nvim",
  event = "VeryLazy",
  priority = 1000,
  config = function()
    require('tiny-inline-diagnostic').setup({
      options = {
        multilines = {
          enabled = true,
          always_show = true,
        },
      }
    })
  end
}
