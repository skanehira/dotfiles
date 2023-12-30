---@diagnostic disable: need-check-nil

-- alias to vim's objects
g = vim.g
opt = vim.opt
cmd = vim.cmd
fn = vim.fn
api = vim.api

-- disable default plugins
local disable_plugins = {
  "loaded_gzip",
  "loaded_shada_plugin",
  "loadedzip",
  "loaded_spellfile_plugin",
  "loaded_tutor_mode_plugin",
  "loaded_gzip",
  "loaded_tar",
  "loaded_tarPlugin",
  "loaded_zip",
  "loaded_zipPlugin",
  "loaded_rrhelper",
  "loaded_2html_plugin",
  "loaded_vimball",
  "loaded_vimballPlugin",
  "loaded_getscript",
  "loaded_getscriptPlugin",
  "loaded_logipat",
  "loaded_matchparen",
  "loaded_man",
  "loaded_netrw",
  "loaded_netrwPlugin",
  "loaded_netrwSettings",
  "loaded_netrwFileHandlers",
  "loaded_logiPat",
  "did_install_default_menus",
  "did_install_syntax_menu",
  "skip_loading_mswin",
}

for _, name in pairs(disable_plugins) do
  g[name] = true
end

-- map functions
_G['map'] = function(mode, lhs, rhs, opt)
  vim.keymap.set(mode, lhs, rhs, opt or { silent = true })
end

for _, mode in pairs({ 'n', 'v', 'i', 'o', 'c', 't', 'x', 't' }) do
  _G[mode .. 'map'] = function(lhs, rhs, opt)
    map(mode, lhs, rhs, opt)
  end
end

-- options
cmd('syntax enable')
cmd('filetype plugin indent on')

g.mapleader = " "
g["markdown_recommended_style"] = 0
opt.breakindent = true
opt.number = false
opt.incsearch = true
opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = true
opt.autoindent = true
opt.smartindent = true
opt.virtualedit = "block"
opt.showtabline = 1
opt.tabstop = 2
opt.shiftwidth = 2
opt.softtabstop = 2
opt.completeopt = 'menu,menuone,noselect'
opt.laststatus = 3
opt.scrolloff = 100
opt.cursorline = true
opt.helplang = 'ja'
opt.autowrite = true
opt.swapfile = false
opt.showtabline = 1
opt.diffopt = 'vertical,internal'
-- opt.wildcharm = ('<Tab>'):byte()
opt.clipboard:append({ fn.has('mac') == 1 and 'unnamed' or 'unnamedplus' })
opt.grepprg = 'rg --vimgrep'
opt.grepformat = '%f:%l:%c:%m'
opt.mouse = {}
--opt.foldmethod = 'expr'
--opt.foldexpr = 'nvim_treesitter#foldexpr()'

-- file indent
local filetype_indent_group = api.nvim_create_augroup('fileTypeIndent', { clear = true })
local file_indents = {
  {
    pattern = 'go',
    command = 'setlocal tabstop=4 shiftwidth=4'
  },
  {
    pattern = 'rust',
    command = 'setlocal tabstop=4 softtabstop=4 shiftwidth=4 expandtab'
  },
  {
    pattern = {
      'javascript',
      'typescriptreact',
      'typescript',
      'vim',
      'lua',
      'yaml',
      'json',
      'sh',
      'zsh',
      'markdown',
      'wast',
      'graphql',
    },

    command = 'setlocal tabstop=2 softtabstop=2 shiftwidth=2 expandtab smartindent autoindent'
  },
}

for _, indent in pairs(file_indents) do
  api.nvim_create_autocmd('FileType', {
    pattern = indent.pattern,
    command = indent.command,
    group = filetype_indent_group
  })
end

-- grep window
api.nvim_create_autocmd('QuickFixCmdPost', {
  pattern = '*grep*',
  command = 'cwindow',
  group = api.nvim_create_augroup('grepWindow', { clear = true }),
})

-- restore cursorline
api.nvim_create_autocmd('BufReadPost',
  {
    pattern = '*',
    callback = function()
      cmd([[
    if line("'\"") > 0 && line("'\"") <= line("$")
      exe "normal! g'\""
    endif
    ]])
    end,
    group = api.nvim_create_augroup('restoreCursorline', { clear = true })
  })

-- persistent undo
local ensure_undo_dir = function()
  local undo_path = fn.expand('~/.config/nvim/undo')
  if fn.isdirectory(undo_path) == 0 then
    fn.mkdir(undo_path, 'p')
  end
  opt.undodir = undo_path
  opt.undofile = true
end
ensure_undo_dir()

-- start insert mode when termopen
api.nvim_create_autocmd("TermOpen", {
  pattern = "*",
  callback = function()
    cmd('startinsert')
    cmd('setlocal scrolloff=0')
  end,
  group = api.nvim_create_augroup("neovimTerminal", { clear = true }),
})

-- auto mkdir
local auto_mkdir = function(dir)
  if fn.isdirectory(dir) == 0 then
    fn.mkdir(dir, 'p')
  end
end
api.nvim_create_autocmd('BufWritePre', {
  pattern = '*',
  callback = function()
    auto_mkdir(fn.expand('<afile>:p:h'))
  end,
  group = api.nvim_create_augroup('autoMkdir', { clear = true })
})

-- create zenn article
api.nvim_create_user_command('ZennCreateArticle',
  function(opts)
    local date = fn.strftime('%Y-%m-%d')
    local slug = date .. '-' .. opts.args
    os.execute('npx zenn new:article --emoji 🦍 --slug ' .. slug)
    cmd('edit ' .. string.format('articles/%s.md', slug))
  end, { nargs = 1 })

-- insert markdown link
local insert_markdown_link = function()
  local old = fn.getreg(9)
  local link = fn.trim(fn.getreg())
  if link:match('^http.*') == nil then
    cmd('normal! p')
    return
  end
  cmd('normal! "9y')
  local word = fn.getreg(9)
  local text = string.format('[%s](%s)', word, link)
  fn.setreg(9, text)
  cmd('normal! gv"9p')
  fn.setreg(9, old)
end

api.nvim_create_autocmd('FileType', {
  pattern = 'markdown',
  callback = function()
    map('x', 'p', function()
      insert_markdown_link()
    end, { silent = true, buffer = true })
  end,
  group = api.nvim_create_augroup("markdownInsertLink", { clear = true }),
})

--- syntax clear
-- api.nvim_create_autocmd('FileType', {
--   pattern = {'go', 'vim', 'javascript', 'typescript', 'rust', 'json'},
--   callback = function ()
--     cmd('syntax clear')
--   end
-- })

-- key mappings

-- text object
omap('8', 'i(')
omap('2', 'i"')
omap('7', 'i\'')
omap('@', 'i`')
omap('[', 'i[')
omap('{', 'i{')
omap('a8', 'a(')
omap('a2', 'a"')
omap('a7', 'a\'')
omap('a@', 'a`')

nmap('v8', 'vi(')
nmap('v2', 'vi"')
nmap('v7', 'vi\'')
nmap('v@', 'vi`')
nmap('v[', 'vi[')
nmap('v{', 'vi{')
nmap('va8', 'va(')
nmap('va2', 'va"')
nmap('va7', 'va\'')
nmap('va@', 'va`')

-- emacs like
imap('<C-k>', '<C-o>C')
imap('<C-f>', '<Right>')
imap('<C-b>', '<Left>')
imap('<C-e>', '<C-o>A')
imap('<C-a>', '<C-o>I')

xmap("*",
  table.concat {
    -- 選択範囲を検索クエリに用いるため、m レジスタに格納。
    -- ビジュアルモードはここで抜ける。
    [["my]],
    -- "m レジスタの中身を検索。
    -- ただし必要な文字はエスケープした上で、空白に関しては伸び縮み可能とする
    [[/\V<C-R><C-R>=substitute(escape(@m, '/\'), '\_s\+', '\\_s\\+', 'g')<CR><CR>]],
    -- 先ほど検索した範囲にカーソルが移るように、手前に戻す
    [[N]],
  },
  {}
)

-- help
api.nvim_create_autocmd("FileType", {
  pattern = "help",
  command = "nnoremap <buffer> <silent>q :bw!<CR>",
  group = api.nvim_create_augroup("helpKeymaps", { clear = true }),
})

-- command line
-- cmap defaults silent to true, but passes an empty setting because the cursor is not updated
cmap('<C-b>', '<Left>', {})
cmap('<C-f>', '<Right>', {})
cmap('<C-a>', '<Home>', {})
cmap('<Up>', '<C-p>')
cmap('<Down>', '<C-n>')
cmap('<C-n>', function()
  return fn.pumvisible() == 1 and '<C-n>' or '<Down>'
end, { expr = true })
cmap('<C-p>', function()
  return fn.pumvisible() == 1 and '<C-p>' or '<Up>'
end, { expr = true })
api.nvim_create_autocmd('FileType', {
  pattern = 'qf',
  callback = function()
    nmap('q', '<Cmd>q<CR>', { silent = true, buffer = true })
  end,
  group = api.nvim_create_augroup("qfInit", { clear = true }),
})

-- paste with <C-v>
map({ 'c', 'i' }, '<C-v>', 'printf("<C-r><C-o>%s", v:register)', { expr = true })

-- other keymap
nmap('<Leader>.', ':tabnew ~/.config/nvim/init.lua<CR>')
nmap('Y', 'Y')
nmap('R', 'gR')
nmap('*', '*N')
nmap('<Esc><Esc>', '<Cmd>nohlsearch<CR>')
nmap('H', '^')
nmap('L', 'g_')
nmap('<C-j>', 'o<Esc>')
nmap('<C-k>', 'O<Esc>')
nmap('o', 'A<CR>')
nmap('<C-l>', 'gt')
nmap('<C-h>', 'gT')
nmap('<Leader>tm', [[:new | terminal<CR>]])
tmap('<C-]>', [[<C-\><C-n>]])
vmap('H', '^')
vmap('L', 'g_')

-- ############################# plugin config section ###############################
-- nvim-cmp
local nvim_cmp_config = function()
  local cmp = require('cmp')
  cmp.setup({
    window = {
      -- completion = cmp.config.window.bordered(),
      documentation = cmp.config.window.bordered(),
    },
    preselect = cmp.PreselectMode.None,
    mapping = cmp.mapping.preset.insert({
      ['<C-b>'] = cmp.mapping.scroll_docs(-4),
      ['<C-f>'] = cmp.mapping.scroll_docs(4),
      ["<C-p>"] = cmp.mapping.select_prev_item(),
      ["<C-n>"] = cmp.mapping.select_next_item(),
      ['<Tab>'] = cmp.mapping.complete(),
      ['<CR>'] = cmp.mapping.confirm({ select = true }),
      ['<C-l>'] = cmp.mapping(function(_)
        vim.api.nvim_feedkeys(vim.fn['copilot#Accept'](vim.api.nvim_replace_termcodes('<Tab>', true, true, true)), 'n',
          true)
      end)
    }),
    experimental = {
      ghost_text = false -- this feature conflict with copilot.vim's preview.
    },
    sources = {
      { name = 'nvim_lsp' },
      { name = 'vsnip' },
      {
        name = 'buffer',
        option = {
          get_bufnrs = function()
            local bufs = {}
            for _, win in ipairs(api.nvim_list_wins()) do
              bufs[api.nvim_win_get_buf(win)] = true
            end
            return vim.tbl_keys(bufs)
          end
        }
      },
      { name = 'path' },
      { name = "crates" },
    },
    view = {
      entries = 'native'
    },
    snippet = {
      expand = function(args)
        fn['vsnip#anonymous'](args.body)
      end
    },
  })
end

-- lsp on attach
Lsp_on_attach = function(client, bufnr)
  -- Enable completion triggered by <c-x><c-o>
  client.server_capabilities.semanticTokensProvider = nil
  api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')
  local bufopts = { silent = true, buffer = bufnr }
  nmap('K', vim.lsp.buf.hover, bufopts)
  nmap('<Leader>gi', vim.lsp.buf.implementation, bufopts)
  nmap('<Leader>gr', vim.lsp.buf.references, bufopts)
  nmap('<Leader>rn', vim.lsp.buf.rename, bufopts)
  nmap(']d', vim.diagnostic.goto_next, bufopts)
  nmap('[d', vim.diagnostic.goto_prev, bufopts)
  nmap('gO', function()
    vim.lsp.buf_request(0, 'experimental/externalDocs', vim.lsp.util.make_position_params(),
      function(_, url)
        if url then
          fn.jobstart({ 'open', url })
        end
      end)
  end, bufopts)
  nmap('<C-g><C-d>', vim.diagnostic.open_float, bufopts)
  if client.name == 'denols' then
    nmap('<C-]>', vim.lsp.buf.definition, bufopts)
  else
    opt.tagfunc = 'v:lua.vim.lsp.tagfunc'
  end
  map({ 'n', 'x' }, 'ma', vim.lsp.buf.code_action, bufopts)
  nmap('<Leader>gl', vim.lsp.codelens.run, bufopts)

  -- auto format when save the file
  local organize_import = function()
  end
  local actions = vim.tbl_get(client.server_capabilities, 'codeActionProvider', "codeActionKinds")
  if actions ~= nil and vim.tbl_contains(actions, "source.organizeImports") then
    organize_import = function()
      vim.lsp.buf.code_action({ context = { only = { "source.organizeImports" } }, apply = true })
    end
  end
  nmap('mi', organize_import)

  if client.supports_method("textDocument/formatting") then
    nmap(']f', vim.lsp.buf.format, { buffer = bufnr })
  end

  -- local augroup = api.nvim_create_augroup("LspFormatting", { clear = false })
  -- if client.supports_method("textDocument/formatting") then
  --   nmap(']f', vim.lsp.buf.format, { buffer = bufnr })
  --   if client.name == 'sumneko_lua' then
  --     return
  --   end
  --   api.nvim_create_autocmd("BufWritePre", {
  --     callback = function()
  --       organize_import()
  --       vim.lsp.buf.format()
  --     end,
  --     group = augroup,
  --     buffer = bufnr,
  --   })
  -- end
end

-- color scheme config
local colorscheme_config = function()
  opt.termguicolors = true
  cmd([[
      colorscheme carbonfox
      hi WinSeparator guifg=#535353
      hi Visual ctermfg=159 ctermbg=23 guifg=#b3c3cc guibg=#384851
      hi DiffAdd guifg=#25be6a
      hi DiffDelete guifg=#ee5396
      ]])
end

-- bufferline.nvim
local bufferline_config = function()
  require('bufferline').setup({
    options = {
      mode = 'tabs',
      hover = {
        enabled = true,
      },
      diagnostics = 'nvim_lsp',
      diagnostics_indicator = function(count, level)
        local icon = level:match("error") and " " or " "
        return ' ' .. icon .. count
      end,
      indicator = {
        icon = '',
      },
      buffer_close_icon = 'x'
    }
  })
end

-- gina.vim
local gina_config = function()
  local gina_keymaps = {
    { map = 'nmap', buffer = 'status', lhs = 'gp', rhs = '<Cmd>Gina push<CR>' },
    { map = 'nmap', buffer = 'status', lhs = 'gr', rhs = '<Cmd>terminal gh pr create<CR>' },
    { map = 'nmap', buffer = 'status', lhs = 'gl', rhs = '<Cmd>Gina pull<CR>' },
    { map = 'nmap', buffer = 'status', lhs = 'cm', rhs = '<Cmd>Gina commit<CR>' },
    { map = 'nmap', buffer = 'status', lhs = 'ca', rhs = '<Cmd>Gina commit --amend<CR>' },
    { map = 'nmap', buffer = 'status', lhs = 'dp', rhs = '<Plug>(gina-patch-oneside-tab)' },
    { map = 'nmap', buffer = 'status', lhs = 'gc', rhs = '<Plug>(gina-chaperon)' },
    { map = 'nmap', buffer = 'status', lhs = 'ga', rhs = '--' },
    { map = 'vmap', buffer = 'status', lhs = 'ga', rhs = '--' },
    { map = 'nmap', buffer = 'log',    lhs = 'dd', rhs = '<Plug>(gina-changes-of)' },
    { map = 'nmap', buffer = 'branch', lhs = 'n',  rhs = '<Plug>(gina-branch-new)' },
    { map = 'nmap', buffer = 'branch', lhs = 'D',  rhs = '<Plug>(gina-branch-delete)' },
    { map = 'nmap', buffer = 'branch', lhs = 'p',  rhs = '<Cmd>terminal gh pr create<CR>' },
    { map = 'nmap', buffer = 'branch', lhs = 'P',  rhs = '<Cmd>terminal gh pr create<CR>' },
    { map = 'nmap', buffer = '/.*',    lhs = 'q',  rhs = '<Cmd>bw<CR>' },
  }
  for _, m in pairs(gina_keymaps) do
    fn['gina#custom#mapping#' .. m.map](m.buffer, m.lhs, m.rhs, { silent = true })
  end

  fn['gina#custom#command#option']('log', '--opener', 'new')
  fn['gina#custom#command#option']('status', '--opener', 'new')
  fn['gina#custom#command#option']('branch', '--opener', 'new')
  nmap('gs', '<Cmd>Gina status<CR>')
  nmap('gl', '<Cmd>Gina log<CR>')
  nmap('gm', '<Cmd>Gina blame<CR>')
  nmap('gb', '<Cmd>Gina branch<CR>')
  nmap('gu', ':Gina browse --exact --yank :<CR>')
  vmap('gu', ':Gina browse --exact --yank :<CR>')
end

-- telescope.vim
local telescope_config = function()
  require("telescope").load_extension("ui-select")
  local actions = require('telescope.actions')
  require('telescope').setup {
    pickers = {
      live_grep = {
        mappings = {
          i = {
            ['<C-o>'] = actions.send_to_qflist + actions.open_qflist,
            ['<C-l>'] = actions.send_to_loclist + actions.open_loclist,
          }
        }
      }
    },
    extensions = {
      ['ui-select'] = {
        require('telescope.themes').get_dropdown {}
      }
    }
  }
end

-- fern.vim
local fern_config = function()
  g['fern#renderer'] = 'nerdfont'
  g['fern#window_selector_use_popup'] = true
  g['fern#default_hidden'] = 1
  g['fern#default_exclude'] = '\\.git$\\|\\.DS_Store'

  api.nvim_create_autocmd('FileType', {
    pattern = 'fern',
    callback = function()
      nmap('q', ':q<CR>', { silent = true, buffer = true })
      nmap('<C-x>', '<Plug>(fern-action-open:split)', { silent = true, buffer = true })
      nmap('<C-v>', '<Plug>(fern-action-open:vsplit)', { silent = true, buffer = true })
      nmap('<C-t>', '<Plug>(fern-action-tcd)', { silent = true, buffer = true })
    end,
    group = api.nvim_create_augroup('fernInit', { clear = true }),
  })
end

-- lsp config
local lsp_config = function()
  local signs = { Error = " ", Warn = " ", Hint = "💡", Info = " " }
  for type, icon in pairs(signs) do
    local hl = "DiagnosticSign" .. type
    vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = hl })
  end

  require('mason-lspconfig').setup({
    automatic_installation = {
      exclude = {
        'gopls',
        'denols',
      }
    }
  })

  local lspconfig = require("lspconfig")

  -- mason-lspconfig will auto install LS when config included in lspconfig
  local lss = {
    'denols',
    'gopls',
    'rust_analyzer',
    'tsserver',
    'volar',
    'lua_ls',
    'golangci_lint_ls',
    'eslint',
    'graphql',
    'bashls',
    'yamlls',
    'jsonls',
    'vimls',
    'marksman',
    'taplo',
    -- need manual install
    -- https://github.com/kitagry/regols
    'regols',
    'clangd',
  }

  local node_root_dir = lspconfig.util.root_pattern("package.json")
  local is_node_repo = node_root_dir(fn.getcwd()) ~= nil

  for _, ls in pairs(lss) do
    (function()
      local opts = {}

      if ls == 'denols' then
        -- dont start LS in nodejs repository
        if is_node_repo then
          return
        end
        opts = {
          cmd = { 'deno', 'lsp' },
          root_dir = lspconfig.util.root_pattern('deps.ts', 'deno.json', 'import_map.json', '.git'),
          settings = {
            deno = {
              lint = true,
              unstable = true,
              suggest = {
                imports = {
                  hosts = {
                    ["https://deno.land"] = true,
                    ["https://cdn.nest.land"] = true,
                    ["https://crux.land"] = true,
                  },
                },
              },
            }
          },
        }
      elseif ls == 'tsserver' then
        if not is_node_repo then
          return
        end

        opts = {
          root_dir = lspconfig.util.root_pattern('package.json', 'node_modules'),
        }
      elseif ls == 'regols' then
        opts = {
          cmd = { 'regols' },
          filetypes = { 'rego' },
          root_dir = lspconfig.util.root_pattern('.git')
        }
      elseif ls == 'lua_ls' then
        opts = {
          settings = {
            Lua = {
              runtime = {
                version = 'LuaJIT'
              },
              diagnostics = {
                -- Get the language server to recognize the `vim` global
                globals = { "vim" },
              },
              workspace = {
                -- Make the server aware of Neovim runtime files
                library = api.nvim_get_runtime_file("", true),
              },
            },
          },
        }
      elseif ls == 'yamlls' then
        opts = {
          settings = {
            yaml = {
              schemas = {
                ['https://json.schemastore.org/github-workflow.json'] = "/.github/workflows/*",
                ['https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json'] = "*compose.y*ml"
              }
            }
          }
        }
      elseif ls == "rust_analyzer" then
        opts = {
          settings = {
            ["rust-analyzer"] = {
              check = {
                command = "clippy"
              },
              diagnostics = {
                experimental = {
                  enable = true,
                }
              }
            }
          }
        }
      end

      opts['on_attach'] = Lsp_on_attach

      lspconfig[ls].setup(opts)
    end)()
  end
end

-- gitsigns.nvim
local gitsigns_config = function()
  require('gitsigns').setup({
    current_line_blame = true,
    on_attach = function(bufnr)
      local gs = package.loaded.gitsigns

      -- Navigation
      map('n', ']c', function()
        if vim.wo.diff then return ']c' end
        vim.schedule(function() gs.next_hunk() end)
        return '<Ignore>'
      end, { expr = true })

      map('n', '[c', function()
        if vim.wo.diff then return '[c' end
        vim.schedule(function() gs.prev_hunk() end)
        return '<Ignore>'
      end, { expr = true })

      local opts = {
        buffer = bufnr,
        silent = true
      }
      -- Actions
      map({ 'n', 'x' }, ']g', ':Gitsigns stage_hunk<CR>', opts)
      map({ 'n', 'x' }, '[g', ':Gitsigns undo_stage_hunk<CR>', opts)
      map({ 'o', 'x' }, 'ih', ':<C-U>Gitsigns select_hunk<CR>', opts)
      nmap('mp', ':Gitsigns preview_hunk<CR>', opts)
    end
  })
end

-- lsp hover config
vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(
  vim.lsp.handlers.hover, {
    border = "single"
  })

-- twihi.vim config
local twihi_config = function()
  nmap('<C-g>n', '<Cmd>TwihiTweet<CR>')
  nmap('<C-g>m', '<Cmd>TwihiMentions<CR>')
  nmap('<C-g>h', '<Cmd>TwihiHome<CR>')

  local twihi_timeline_keymap = function()
    local opt = { buffer = true, silent = true }
    nmap('<C-g><C-y>', '<Plug>(twihi:tweet:yank)', opt)
    nmap('R', '<Plug>(twihi:retweet)', opt)
    nmap('<C-g><C-l>', '<C-g><C-l> <Plug>(twihi:tweet:like)', opt)
    nmap('<C-o>', '<Plug>(twihi:tweet:open)', opt)
    nmap('<C-r>', '<Plug>(twihi:reply)', opt)
    nmap('<C-j>', '<Plug>(twihi:tweet:next)', opt)
    nmap('<C-k>', '<Plug>(twihi:tweet:prev)', opt)
  end

  local twihi_media_keymap = function()
    local opt = { buffer = true, silent = true }
    nmap('<C-g>m', '<Plug>(twihi:media:add:clipboard)', opt)
    nmap('<C-g>d', '<Plug>(twihi:media:remove)', opt)
    nmap('<C-g>o', '<Plug>(twihi:media:open)', opt)
  end

  local twihi_init_group = api.nvim_create_augroup("twihiInit", { clear = true })
  api.nvim_create_autocmd('FileType', {
    pattern = 'twihi-timeline',
    callback = function()
      twihi_timeline_keymap()
    end,
    group = twihi_init_group,
  })

  api.nvim_create_autocmd('FileType', {
    pattern = { 'twihi-reply', 'twihi-tweet', 'twihi-retweet' },
    callback = function()
      twihi_media_keymap()
    end,
    group = twihi_init_group,
  })

  -- g['twihi_mention_check_interval'] = 30000 * 10
  -- g['twihi_notify_ui'] = 'system'
end

-- k8s.vim
local k8s_config = function()
  local k8s_pods_keymap = function()
    nmap('<CR>', '<Plug>(k8s:pods:containers)', { buffer = true })
    nmap('<C-g><C-l>', '<Plug>(k8s:pods:logs)', { buffer = true })
    nmap('<C-g><C-d>', '<Plug>(k8s:pods:describe)', { buffer = true })
    -- nmap('D', '<Plug>(k8s:pods:delete)', { buffer = true })
    -- nmap('K', '<Plug>(k8s:pods:kill)', { buffer = true })
    nmap('<C-g><C-y>', '<Plug>(k8s:pods:yaml)', { buffer = true })
    nmap('<C-e>', '<Plug>(k8s:pods:events)', { buffer = true })
    nmap('s', '<Plug>(k8s:pods:shell)', { buffer = true })
    nmap('e', '<Plug>(k8s:pods:exec)', { buffer = true })
    -- nmap('E', '<Plug>(k8s:pods:edit)', { buffer = true })
  end

  local k8s_nodes_keymap = function()
    nmap('<C-g><C-d>', '<Plug>(k8s:nodes:describe)', { buffer = true })
    nmap('<C-g><C-y>', '<Plug>(k8s:nodes:yaml)', { buffer = true })
    nmap('<CR>', '<Plug>(k8s:nodes:pods)', { buffer = true })
    nmap('E', '<Plug>(k8s:nodes:edit)', { buffer = true })
  end

  local k8s_containers_keymap = function()
    nmap('s', '<Plug>(k8s:pods:containers:shell)', { buffer = true })
    nmap('e', '<Plug>(k8s:pods:containers:exec)', { buffer = true })
  end

  local k8s_deployments_keymap = function()
    nmap('<C-g><C-d>', '<Plug>(k8s:deployments:describe)', { buffer = true })
    nmap('<C-g><C-y>', '<Plug>(k8s:deployments:yaml)', { buffer = true })
    nmap('E', '<Plug>(k8s:deployments:edit)', { buffer = true })
    nmap('<CR>', '<Plug>(k8s:deployments:pods)', { buffer = true })
    nmap('D', '<Plug>(k8s:deployments:delete)', { buffer = true })
  end

  local k8s_services_keymap = function()
    nmap('<CR>', '<Plug>(k8s:svcs:pods)', { buffer = true })
    nmap('<C-g><C-d>', '<Plug>(k8s:svcs:describe)', { buffer = true })
    nmap('D', '<Plug>(k8s:svcs:delete)', { buffer = true })
    nmap('<C-g><C-y>', '<Plug>(k8s:svcs:yaml)', { buffer = true })
    nmap('E', '<Plug>(k8s:svcs:edit)', { buffer = true })
  end

  local k8s_secrets_keymap = function()
    nmap('<C-g><C-d>', '<Plug>(k8s:secrets:describe)', { buffer = true })
    nmap('<C-g><C-y>', '<Plug>(k8s:secrets:yaml)', { buffer = true })
    nmap('E', '<Plug>(k8s:secrets:edit)', { buffer = true })
    nmap('D', '<Plug>(k8s:secrets:delete)', { buffer = true })
  end

  local k8s_keymaps = {
    { ft = 'k8s-pods',        fn = k8s_pods_keymap },
    { ft = 'k8s-nodes',       fn = k8s_nodes_keymap },
    { ft = 'k8s-containers',  fn = k8s_containers_keymap },
    { ft = 'k8s-deployments', fn = k8s_deployments_keymap },
    { ft = 'k8s-services',    fn = k8s_services_keymap },
    { ft = 'k8s-secrets',     fn = k8s_secrets_keymap },
  }

  local k8s_keymap_group = api.nvim_create_augroup("k8sInit", { clear = true })

  for _, m in pairs(k8s_keymaps) do
    api.nvim_create_autocmd('FileType', {
      pattern = m.ft,
      callback = m.fn,
      group = k8s_keymap_group,
    })
  end
end

-- silicon.vim
g['silicon_options'] = {
  font = 'Cica',
  no_line_number = true,
  -- background_color = '#434C5E',
  no_window_controls = true,
  theme = 'GitHub',
}
local silicon_config = function()
  nmap('gi', '<Plug>(silicon-generate)')
  xmap('gi', '<Plug>(silicon-generate)')
end

-- graphql.vim
local graphql_config = function()
  api.nvim_create_autocmd('FileType', {
    pattern = 'graphql',
    callback = function()
      nmap('gp', '<Plug>(graphql-execute)')
    end,
    group = api.nvim_create_augroup("graphqlInit", { clear = true }),
  })
end

-- translate.vim
local translate_config = function()
  nmap('gr', '<Plug>(Translate)')
  vmap('gr', '<Plug>(Translate)')
end

-- quickrun.vim
g['quickrun_config'] = {
  typescript = {
    command = 'deno',
    tempfile = '%{printf("%s.ts", tempname())}',
    cmdopt = '--no-check --unstable --allow-all',
    exec = { 'NO_COLOR=1 %C run %o %s' },
  },
  ['deno/terminal'] = {
    command = 'deno',
    tempfile = '%{printf("%s.ts", tempname())}',
    cmdopt = '--no-check --unstable --allow-all',
    exec = { '%C run %o %s' },
    type = 'typescript',
    runner = 'neoterm',
  },
  ['rust/cargo'] = {
    command = 'cargo',
    exec = '%C run --quiet %s %a',
  },
}

local quickrun_config = function()
  api.nvim_create_autocmd('FileType', {
    pattern = 'quickrun',
    callback = function()
      nmap('q', '<Cmd>bw!<CR>', { silent = true, buffer = true })
    end,
    group = api.nvim_create_augroup('quickrunInit', { clear = true }),
  })
end

-- vim-markdown
g['vim_markdown_folding_disabled'] = true

-- emmet
g['emmet_html5'] = false
g['user_emmet_install_global'] = false
g['user_emmet_settings'] = {
  variables = {
    lang = 'ja'
  }
}
g['user_emmet_leader_key'] = '<C-g>'
local emmet_config = function()
  api.nvim_create_autocmd('FileType', {
    pattern = { 'vue', 'html', 'css', 'typescriptreact' },
    command = 'EmmetInstall',
    group = api.nvim_create_augroup("emmetInstall", { clear = true }),
  })
end

-- vim-sonictemplate.vim
local sonictemplate_config = function()
  imap('<C-g><C-l>', '<plug>(sonictemplate-postfix)')
  g['sonictemplate_author'] = 'skanehira'
  g['sonictemplate_license'] = 'MIT'
  g['sonictemplate_vim_template_dir'] = fn.expand('~/.vim/sonictemplate')
end

-- vimhelpgenerator
g['vimhelpgenerator_version'] = ''
g['vimhelpgenerator_author'] = 'Author: skanehira <sho19921005@gmail.com>'
g['vimhelpgenerator_uri'] = 'https://github.com/skanehira/'
g['vimhelpgenerator_defaultlanguage'] = 'en'

-- gyazo.vim
g['gyazo_insert_markdown'] = true
local gyazo_config = function()
  nmap('gup', '<Plug>(gyazo-upload)')
end

-- winselector.vim
local winselector_config = function()
  nmap('<C-f>', '<Plug>(winselector)')
end

-- test.vim
-- local test_config = function()
--   g['test#javascript#denotest#options'] = { all = '--parallel --unstable -A' }
--   g['test#rust#cargotest#options'] = { all = '-- --nocapture' }
--   g['test#go#gotest#options'] = { all = '-v' }
--   nmap('<Leader>tn', '<Cmd>TestNearest<CR>')
-- end

-- open-browser.vim
local openbrowser_config = function()
  nmap('gop', '<Plug>(openbrowser-open)')
end

-- lualine
local lualine_config = function()
  require('lualine').setup({
    sections = {
      lualine_c = {
        {
          'filename',
          path = 3,
        }
      }
    }
  })
end

-- treesitter config
local treesitter_config = function()
  require('nvim-treesitter.configs').setup({
    ensure_installed = {
      'lua', 'rust', 'typescript', 'tsx',
      'go', 'gomod', 'sql', 'toml', 'yaml',
      'html', 'javascript', 'graphql',
      'markdown', 'markdown_inline',
    },
    auto_install = true,
    highlight = {
      enable = true,
      disable = { 'yaml' },
    }
  })
end

-- indent_blankline config
local indent_blankline = function()
  require('ibl').setup {
    indent = {
      tab_char = '>'
    },
  }
  cmd([[hi IndentBlanklineChar guifg=#353535]])
end

-- ############################# lazy config section ###############################
-- lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- lazy settings
require("lazy").setup({
  {
    'jose-elias-alvarez/null-ls.nvim',
    event = { 'BufRead', 'BufNewFile' },
    dependencies = {
      { 'nvim-lua/plenary.nvim' },
    },
    config = function()
      local null_ls = require('null-ls')
      null_ls.setup({
        sources = {
          null_ls.builtins.formatting.prettier.with {
            prefer_local = 'node_modules/.bin',
            condition = function(utils)
              -- https://prettier.io/docs/en/configuration.html
              return utils.root_has_file {
                '.prettierrc',
                '.prettierrc.js',
                '.prettierrc.cjs',
                '.prettierrc.json',
                '.prettierrc.yml',
                '.prettierrc.yaml',
                'prettier.config.js',
                'prettier.config.cjs',
              }
            end,
          },
          null_ls.builtins.diagnostics.actionlint,
          null_ls.builtins.diagnostics.textlint.with {
            prefer_local = 'node_modules/.bin',
            condition = function(utils)
              return utils.root_has_file {
                '.textlintrc',
                '.textlintrc.js',
                '.textlintrc.json',
                '.textlintrc.yml',
                '.textlintrc.yaml',
              }
            end,
          },
        }
      })
    end
  },
  {
    'github/copilot.vim',
    event = { 'BufRead', 'BufNewFile' },
    config = function()
      g['copilot_no_tab_map'] = 1
      imap('<Plug>(vimrc:copilot-dummy-map)', 'copilot#Accept("\\<Tab>")', { expr = true })
    end
  },
  {
    'tyru/operator-camelize.vim',
    dependencies = {
      'kana/vim-operator-user'
    },
    config = function()
      vmap('<Leader>c', '<plug>(operator-camelize-toggle)')
    end
  },
  {
    'vim-skk/skkeleton',
    init = function()
      api.nvim_create_autocmd('User', {
        pattern = 'skkeleton-initialize-pre',
        callback = function()
          vim.call('skkeleton#config', {
            globalJisyo = vim.fn.expand('~/.config/skk/SKK-JISYO.L'),
            eggLikeNewline = true,
            keepState = true
          })
        end,
        group = api.nvim_create_augroup('skkelectonInitPre', { clear = true }),
      })
    end,
    config = function()
      imap('<C-j>', '<Plug>(skkeleton-toggle)')
      cmap('<C-j>', '<Plug>(skkeleton-toggle)')
    end
  },
  {
    'lambdalisue/kensaku.vim'
  },
  {
    'lambdalisue/kensaku-search.vim',
    config = function()
      cmap('<CR>', '<Plug>(kensaku-search-replace)<CR>', {})
    end
  },
  {
    'thinca/vim-qfreplace',
    event = { 'BufNewFile', 'BufRead' }
  },
  {
    'dhruvasagar/vim-zoom',
    keys = {
      { '<C-w>m', '<Cmd>call zoom#toggle()<CR>' }
    },
  },
  {
    'mattn/vim-goimports',
    ft = 'go',
  },
  -- { 'https://git.sr.ht/~whynothugo/lsp_lines.nvim',
  --   config = function()
  --     vim.diagnostic.config({ virtual_text = false })
  --     require("lsp_lines").setup()
  --   end
  -- },
  --{
  --  'lukas-reineke/indent-blankline.nvim',
  --  event = 'BufReadPre',
  --  config = indent_blankline,
  --},
  {
    'ray-x/lsp_signature.nvim',
    event = { 'BufRead', 'BufNewFile' },
    config = function()
      require('lsp_signature').setup({})
    end
  },
  {
    'lewis6991/gitsigns.nvim',
    event = { 'BufRead', 'BufNewFile' },
    config = gitsigns_config
  },
  {
    'nvim-lualine/lualine.nvim',
    dependencies = 'kyazdani42/nvim-web-devicons',
    config = lualine_config,
  },
  {
    'akinsho/bufferline.nvim',
    dependencies = 'kyazdani42/nvim-web-devicons',
    config = bufferline_config
  },
  {
    'EdenEast/nightfox.nvim',
    lazy = false,
    config = colorscheme_config,
  },
  {
    'kevinhwang91/nvim-bqf',
    ft = 'qf',
    event = { 'QuickFixCmdPre' }
  },
  {
    'williamboman/mason-lspconfig.nvim',
    event = { 'BufReadPre', 'BufNewFile' },
    dependencies = {
      { 'neovim/nvim-lspconfig' },
      {
        'williamboman/mason.nvim',
        config = function() require("mason").setup() end,
      },
    },
    config = lsp_config,
  },
  {
    'j-hui/fidget.nvim',
    tag = "legacy",
    config = function() require('fidget').setup() end,
  },
  {
    'hrsh7th/nvim-cmp',
    -- module = { "cmp" },
    dependencies = {
      { 'hrsh7th/cmp-nvim-lsp' },
      { 'hrsh7th/cmp-buffer' },
      { 'hrsh7th/cmp-path' },
      { 'hrsh7th/cmp-vsnip' },
      { 'hrsh7th/vim-vsnip' },
    },
    config = nvim_cmp_config,
    event = { 'InsertEnter' },
  },
  {
    'nvim-treesitter/nvim-treesitter',
    build = ':TSUpdate',
    config = treesitter_config
  },
  {
    'windwp/nvim-autopairs',
    event = { 'InsertEnter' },
    config = function()
      require("nvim-autopairs").setup({ map_c_h = true })
    end,
  },
  -- {
  --   'vim-test/vim-test',
  --   event = 'BufRead',
  --   config = test_config,
  -- },
  {
    'lambdalisue/fern-hijack.vim',
    dependencies = {
      'lambdalisue/fern.vim',
      cmd = 'Fern',
      config = fern_config,
    },
    init = function()
      nmap('<Leader>f', '<Cmd>Fern . -drawer<CR>', { silent = true })
    end
  },
  {
    'lambdalisue/fern-renderer-nerdfont.vim',
    dependencies = {
      'lambdalisue/fern.vim',
      'lambdalisue/nerdfont.vim',
    },
    config = function()
      g['fern#renderer'] = 'nerdfont'
    end
  },
  {
    'lambdalisue/gina.vim',
    config = gina_config,
  },
  {
    'lambdalisue/guise.vim',
  },
  {
    'mattn/emmet-vim',
    event = { 'BufRead', 'BufNewFile' },
    config = emmet_config
  },
  {
    'mattn/vim-sonictemplate',
    event = { 'InsertEnter' },
    config = sonictemplate_config,
  },
  {
    'simeji/winresizer',
    keys = {
      { '<C-e>', '<Cmd>WinResizerStartResize<CR>', desc = 'start window resizer' }
    },
  },
  { 'vim-denops/denops.vim' },
  {
    'skanehira/denops-silicon.vim',
    config = silicon_config
  },
  {
    'skanehira/denops-docker.vim',
    config = function()
      nmap('gdc', '<Cmd>new | DockerContainers<CR>', {})
      nmap('gdi', '<Cmd>new | DockerImages<CR>', {})
    end
  },
  {
    'thinca/vim-quickrun',
    dependencies = {
      { 'skanehira/quickrun-neoterm.vim' }
    },
    config = quickrun_config,
  },
  {
    'tyru/open-browser-github.vim',
    dependencies = {
      {
        'tyru/open-browser.vim',
        config = openbrowser_config,
      },
    }
  },
  {
    'skanehira/denops-graphql.vim',
    config = graphql_config
  },
  { 'thinca/vim-prettyprint' },
  {
    'skanehira/k8s.vim',
    config = k8s_config,
  },
  {
    'skanehira/winselector.vim',
    config = winselector_config,
  },
  {
    'nvim-telescope/telescope.nvim',
    dependencies = {
      { 'nvim-lua/plenary.nvim' },
      { 'nvim-telescope/telescope-ui-select.nvim' },
    },
    init = function()
      local function builtin(name)
        return function(opt)
          return function()
            return require('telescope.builtin')[name](opt or {})
          end
        end
      end

      local function egrepify()
        require('telescope').extensions.egrepify.egrepify({})
      end

      nmap('<C-p>', builtin('find_files')())
      nmap('mg', egrepify)
      nmap('md', builtin('diagnostics')())
      nmap('mf', builtin('current_buffer_fuzzy_find')())
      nmap('mh', builtin('help_tags')({ lang = 'ja' }))
      nmap('mo', builtin('oldfiles')())
      nmap('ms', builtin('git_status')())
      nmap('mc', builtin('commands')())
      nmap('<Leader>s', builtin('lsp_document_symbols')())
    end,
    config = telescope_config,
  },
  -- for documentation
  { 'glidenote/memolist.vim', cmd = { 'MemoList', 'MemoNew' } },
  { 'godlygeek/tabular',      event = { 'BufRead', 'BufNewFile' } },
  -- { 'gyim/vim-boxdraw' }
  { 'mattn/vim-maketable',    event = { 'BufRead', 'BufNewFile' } },
  -- { 'shinespark/vim-list2tree' }
  {
    'skanehira/gyazo.vim',
    config = gyazo_config,
    ft = 'markdown',
  },
  {
    'skanehira/denops-translate.vim',
    config = translate_config
  },
  { 'vim-jp/vimdoc-ja' },
  { 'plasticboy/vim-markdown',   ft = 'markdown' },
  { 'previm/previm',             ft = 'markdown' },

  -- for develop vim plugins
  { 'LeafCage/vimhelpgenerator', ft = 'vim' },
  { 'lambdalisue/vital-Whisky',  ft = 'vim' },
  { 'tweekmonster/helpful.vim' },
  { 'vim-jp/vital.vim' },
  { 'thinca/vim-themis',         ft = 'vim' },
  { 'tyru/capture.vim' },
  {
    'monaqa/dial.nvim',
    config = function()
      local dial = require("dial.map")
      nmap("<C-a>", dial.inc_normal())
      nmap("<C-x>", dial.dec_normal())
      nmap("g<C-a>", dial.inc_gnormal())
      nmap("g<C-x>", dial.dec_gnormal())
      vmap("<C-a>", dial.inc_visual())
      vmap("<C-x>", dial.dec_visual())
      vmap("g<C-a>", dial.inc_gvisual())
      vmap("g<C-x>", dial.dec_gvisual())
    end
  },
  {
    'Saecki/crates.nvim',
    dependencies = {
      { 'nvim-lua/plenary.nvim' },
    },
    config = function()
      require('crates').setup({
        null_ls = {
          enabled = true,
          name = "crates.nvim",
        },
      })
    end
  },
  {
    'pwntester/octo.nvim',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-telescope/telescope.nvim',
      'kyazdani42/nvim-web-devicons',
    },
    config = function()
      require('octo').setup()
    end
  },
  {
    "fdschmidt93/telescope-egrepify.nvim",
    dependencies = {
      "nvim-telescope/telescope.nvim",
      "nvim-lua/plenary.nvim"
    },
    config = function()
      require("telescope").load_extension("ui-select")
    end
  },
  {
    'thinca/vim-showtime'
  },
  {
    'shellRaining/hlchunk.nvim',
    event = { 'UIEnter' },
    config = function()
      require('hlchunk').setup({
        blank = {
          enable = false,
        }
      })
    end
  },
})
