local copilotChat = {
  "CopilotC-Nvim/CopilotChat.nvim",
  branch = "canary",
  dependencies = {
    { "github/copilot.vim" },
    { "nvim-lua/plenary.nvim" },
  },
  -- opts がないとコマンド出てこない
  opts = {
  },
}

return copilotChat
