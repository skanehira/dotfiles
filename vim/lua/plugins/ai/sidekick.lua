return {
  "folke/sidekick.nvim",
  config = function()
    require("sidekick").setup({
      cli = {
        mux = {
          backend = "tmux",
          enabled = true,
        },
        nes = { enabled = false },
        win = {
          keys = {
            nav_left = { '<C-]><C-h>', 'nav_left' }
          }
        },
        tools = {
          claude_resume = {
            cmd = { 'claude', '-r' },
          },
          claude_continue = {
            cmd = { 'claude', '-c' },
          },
        }
      },
    })

    -- Transparent
    vim.cmd([[
      hi NormalFloat ctermbg=none guibg=none
    ]])

    -- Keymappings
    vim.keymap.set("i", "<tab>", function()
      -- if there is a next edit, jump to it, otherwise apply it if any
      if not require("sidekick").nes_jump_or_apply() then
        return "<Tab>" -- fallback to normal tab
      end
    end, { expr = true, desc = "Goto/Apply Next Edit Suggestion" })

    vim.keymap.set("n", "<leader>as", function()
      require("sidekick.cli").select()
    end, { desc = "Select CLI" })

    vim.keymap.set({ "x", "n" }, "<leader>at", function()
      require("sidekick.cli").send({ msg = "{this}" })
    end, { desc = "Send This" })

    vim.keymap.set("n", "<leader>af", function()
      require("sidekick.cli").send({ msg = "{file}" })
    end, { desc = "Send File" })

    vim.keymap.set({ "n", "x" }, "<leader>ap", function()
      require("sidekick.cli").prompt()
    end, { desc = "Sidekick Select Prompt" })

    vim.keymap.set("n", "<leader>ac", function()
      require("sidekick.cli").toggle({ name = "claude", focus = true })
    end, { desc = "Sidekick Toggle Claude" })

    vim.keymap.set("n", "<leader>ar", function()
      require("sidekick.cli").toggle({ name = "claude_resume", focus = true })
    end, { desc = "Sidekick Toggle Claude Resume" })

    vim.keymap.set("n", "<leader>aC", function()
      require("sidekick.cli").toggle({ name = "claude_continue", focus = true })
    end, { desc = "Sidekick Toggle Claude Continue" })

  end,
}
