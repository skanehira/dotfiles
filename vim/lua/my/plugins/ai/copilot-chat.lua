local copilotChat = {
  'CopilotC-Nvim/CopilotChat.nvim',
  branch = 'main',
  dependencies = {
    { 'zbirenbaum/copilot.lua' },
    { 'nvim-lua/plenary.nvim' },
  },
  opts = {
    model = 'claude-3.7-sonnet-thought',
    window = {
      layout = 'float'
    },
    prompts = {
      Commit = {
        prompt = '$gpt-4o Write commit message for the change with commitizen convention. Keep the title under 50 characters and wrap message at 72 characters. Format as a gitcommit code block.',
        context = { 'buffer', 'git:staged' }
      }
    }
  },
  keys = {
    {
      '<Leader>cc',
      function()
        local actions = require('CopilotChat.actions')
        require('CopilotChat.integrations.telescope').pick(actions.prompt_actions())
      end,
      desc = 'CopilotChat - Prompt actions',
      mode = {
        'n',
        'v',
      },
    },
    {
      '<Leader>co',
      function()
        local chat = require('CopilotChat')
        chat.open()
      end,
      desc = 'CopilotChat - Open chat',
      mode = {
        'n',
        'v',
      },
    }
  },
}

return copilotChat
