-- nvim-treesitter `main` ブランチ (旧 master は archive 済 + Neovim 0.12 と非互換)。
-- 新 API: setup の宣言だけでは何も走らず、install / highlight / textobjects を
-- 個別に明示的に呼ぶ必要がある。
local parsers = {
  'lua', 'rust', 'typescript', 'tsx', 'go', 'gomod',
  'sql', 'toml', 'yaml', 'html', 'javascript',
  'graphql', 'markdown', 'markdown_inline',
}

local treesitter = {
  'nvim-treesitter/nvim-treesitter',
  branch = 'main',
  lazy = false,         -- main は lazy-load 非対応 (README 警告)
  build = ':TSUpdate',
  config = function()
    -- 上記 parsers を install (idempotent、async)。tree-sitter CLI が PATH に
    -- 必要 (packages.nix で tree-sitter を追加済)
    require('nvim-treesitter').install(parsers)

    -- highlight enable は filetype ごとの autocmd で行う (旧 highlight.enable=true 相当)。
    -- yaml はパフォーマンス問題で除外 (旧設定 disable={'yaml'} を踏襲)
    vim.api.nvim_create_autocmd('FileType', {
      callback = function(ev)
        if ev.match == 'yaml' then return end
        pcall(vim.treesitter.start, ev.buf)
      end,
    })
  end,
  dependencies = {
    {
      'nvim-treesitter/nvim-treesitter-textobjects',
      branch = 'main',
      init = function()
        -- 組み込み ftplugin の text-object map と衝突しないよう無効化
        vim.g.no_plugin_maps = true
      end,
      config = function()
        require('nvim-treesitter-textobjects').setup({
          select = {
            lookahead = true,
            selection_modes = {
              ['@parameter.outer'] = 'v',
              ['@function.outer'] = 'V',
            },
            include_surrounding_whitespace = true,
          },
          move = { set_jumps = true },
        })

        local select = require('nvim-treesitter-textobjects.select')
        local swap = require('nvim-treesitter-textobjects.swap')
        local move = require('nvim-treesitter-textobjects.move')

        -- select (旧 textobjects.select.keymaps)
        vim.keymap.set({ 'x', 'o' }, 'af', function()
          select.select_textobject('@function.outer', 'textobjects')
        end)
        vim.keymap.set({ 'x', 'o' }, 'if', function()
          select.select_textobject('@function.inner', 'textobjects')
        end)

        -- swap (旧 textobjects.swap.swap_next/swap_previous)
        vim.keymap.set('n', '<leader>an', function()
          swap.swap_next('@parameter.inner')
        end)
        vim.keymap.set('n', '<leader>aN', function()
          swap.swap_previous('@parameter.inner')
        end)

        -- move (旧 textobjects.move.goto_next_start/goto_previous_start)
        vim.keymap.set({ 'n', 'x', 'o' }, ']]', function()
          move.goto_next_start('@function.outer', 'textobjects')
        end)
        vim.keymap.set({ 'n', 'x', 'o' }, '[[', function()
          move.goto_previous_start('@function.outer', 'textobjects')
        end)
      end,
    },
  },
}

return treesitter
