-- nvim-treesitter `main` ブランチ (旧 master は archive 済 + Neovim 0.12 と非互換)。
-- 新 API: setup の宣言だけでは何も走らず、install / highlight / textobjects を
-- 個別に明示的に呼ぶ必要がある。
local parsers = {
  'lua', 'rust', 'typescript', 'tsx', 'go', 'gomod',
  'sql', 'toml', 'yaml', 'html', 'javascript',
  'graphql', 'markdown', 'markdown_inline',
  'nix', 'bash', 'json', 'gitignore'
}

local treesitter = {
  'nvim-treesitter/nvim-treesitter',
  branch = 'main',
  lazy = false,         -- main は lazy-load 非対応 (README 警告)
  build = ':TSUpdate',
  config = function()
    -- 常用 parser は起動時に事前 install (idempotent、async)。tree-sitter CLI が
    -- PATH に必要 (packages.nix で tree-sitter を追加済)
    require('nvim-treesitter').install(parsers)

    -- highlight enable は filetype ごとの autocmd で行う (旧 highlight.enable=true 相当)。
    -- 未 install な parser は on-demand で install してから start する (旧 auto_install 相当)。
    -- 除外:
    --   diff: main branch の queries/diff/highlights.scm の captures が現行
    --         colorscheme と噛み合わず無色化する。組み込み :syntax の方が綺麗
    local skip_filetypes = { diff = true }
    vim.api.nvim_create_autocmd('FileType', {
      callback = function(ev)
        if skip_filetypes[ev.match] then return end

        -- filetype → ts language 名。get_lang は明示 register された filetype のみ
        -- 値を返すため、未 register なら filetype 名をそのまま parser 名として使う
        -- (typescriptreact → tsx 等の register 済はズレを吸収、diff/nix 等は同名で解決)
        local lang = vim.treesitter.language.get_lang(ev.match) or ev.match
        if lang == '' then return end

        -- parser バイナリの有無で install 済みかを判定 (runtimepath 上に
        -- parser/<lang>.so があれば installed)
        local installed = #vim.api.nvim_get_runtime_file('parser/' .. lang .. '.so', false) > 0

        if installed then
          pcall(vim.treesitter.start, ev.buf, lang)
          return
        end

        -- nvim-treesitter が対応していない言語は何もしない (fern, fidget 等の
        -- プラグイン由来 filetype を install しようとして警告を出さない)
        if not vim.tbl_contains(require('nvim-treesitter.config').get_available(), lang) then
          return
        end

        require('nvim-treesitter').install({ lang }):await(function(err)
          if err then
            vim.schedule(function()
              vim.notify(
                ('nvim-treesitter: failed to install parser %q: %s'):format(lang, err),
                vim.log.levels.WARN
              )
            end)
            return
          end
          if vim.api.nvim_buf_is_valid(ev.buf) then
            pcall(vim.treesitter.start, ev.buf, lang)
          end
        end)
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
