return {
  -- 'johnseth97/codex.nvim',
  dir = '~/dev/github.com/skanehira/codex.nvim',
  lazy = true,
  cmd = { 'Codex', 'CodexToggle' }, -- Optional: Load only on command execution
  keys = {
    {
      '<leader>cc', -- Change this to your preferred keybinding
      function() require('codex').toggle() end,
      desc = 'Toggle Codex popup',
    },
    {
      '<leader>cr', -- Change this to your preferred keybinding
      function() require('codex').resume() end,
      desc = 'Rsume Codex',
    },
  },
  opts = {
    keymaps     = {
      toggle = nil,          -- Keybind to toggle Codex window (Disabled by default, watch out for conflicts)
      quit = '<C-g><C-d>',   -- Keybind to close the Codex window (default: Ctrl + q)
    },                       -- Disable internal default keymap (<leader>cc -> :CodexToggle)
    border      = 'rounded', -- Options: 'single', 'double', or 'rounded'
    width       = 0.8,       -- Width of the floating window (0.0 to 1.0)
    height      = 0.8,       -- Height of the floating window (0.0 to 1.0)
    autoinstall = false,     -- Automatically install the Codex CLI if not found
  },
}
