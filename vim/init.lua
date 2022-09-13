---@diagnostic disable: need-check-nil
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
  vim.g[name] = true
end

-- helper functions
_G['map'] = function(mode, lhs, rhs, opt)
  vim.keymap.set(mode, lhs, rhs, opt or { silent = true })
end

for _, mode in pairs({ 'n', 'v', 'i', 'o', 'c', 't', 'x', 't' }) do
  _G[mode .. 'map'] = function(lhs, rhs, opt)
    vim.keymap.set(mode, lhs, rhs, opt)
  end
end

-- nvim-cmp
local nvim_cmp_config = function()
  local cmp = require('cmp')
  cmp.setup({
    mapping = cmp.mapping.preset.insert({
      ['<C-b>'] = cmp.mapping.scroll_docs(-4),
      ['<C-f>'] = cmp.mapping.scroll_docs(4),
      ["<C-p>"] = cmp.mapping.select_prev_item(),
      ["<C-n>"] = cmp.mapping.select_next_item(),
      ['<Tab>'] = cmp.mapping.complete(),
      ['<CR>'] = cmp.mapping.confirm({ select = true }),
    }),
    sources = {
      { name = 'nvim_lsp' },
      { name = 'vsnip' },
      { name = 'buffer', option = {
        get_bufnrs = function()
          local bufs = {}
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            bufs[vim.api.nvim_win_get_buf(win)] = true
          end
          return vim.tbl_keys(bufs)
        end
      } },
      { name = 'path' },
    },
    snippet = {
      expand = function(args)
        vim.fn['vsnip#anonymous'](args.body)
      end
    },
  })
end

-- lsp on attach
Lsp_on_attach = function(client, bufnr)
  -- Enable completion triggered by <c-x><c-o>
  vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')
  local bufopts = { silent = true, buffer = bufnr }
  nmap('K', vim.lsp.buf.hover, bufopts)
  nmap('<Leader>gi', vim.lsp.buf.implementation, bufopts)
  nmap('<Leader>gr', vim.lsp.buf.references, bufopts)
  nmap('<Leader>rn', vim.lsp.buf.rename, bufopts)
  nmap('<C-]>', vim.lsp.buf.definition, bufopts)
  nmap('ma', vim.lsp.buf.code_action, bufopts)
  nmap('<Leader>gl', vim.lsp.codelens.run, bufopts)

  -- auto format when save the file
  local augroup = vim.api.nvim_create_augroup("LspFormatting", { clear = false })
  if client.supports_method("textDocument/formatting") then
    nmap(';f', vim.lsp.buf.format, { buffer = bufnr })
    if client.name == 'sumneko_lua' then
      return
    end
    vim.api.nvim_create_autocmd("BufWritePre", {
      callback = function()
        vim.lsp.buf.format()
      end,
      group = augroup,
      buffer = bufnr,
    })
  end
end

-- rust-tools.nvim
local rust_tools_config = function()
  local rt = require("rust-tools")
  rt.setup({
    server = {
      on_attach = function(client, bufnr)
        local bufopts = { silent = true, buffer = bufnr }
        Lsp_on_attach(client, bufnr)
        nmap('K', rt.hover_actions.hover_actions, bufopts)
        nmap('<Leader>gl', rt.code_action_group.code_action_group, bufopts)
      end,
      standalone = true,
    },
    tools = {
      hover_actions = {
        border = {
          { '╭', 'NormalFloat' },
          { '─', 'NormalFloat' },
          { '╮', 'NormalFloat' },
          { '│', 'NormalFloat' },
          { '╯', 'NormalFloat' },
          { '─', 'NormalFloat' },
          { '╰', 'NormalFloat' },
          { '│', 'NormalFloat' },
        },
        auto_focus = true,
      },
    }
  })
end

-- iceberg.vim
local iceberg_config = function()
  vim.opt.termguicolors = true
  vim.cmd('colorscheme iceberg')
  vim.api.nvim_create_autocmd('FileType', {
    pattern = '*',
    callback = function()
      vim.cmd([[
      hi clear VertSplit
      hi VertSplit ctermfg=232 guifg=#202023
    ]] )
    end,
    group = vim.api.nvim_create_augroup('icebergGroup', { clear = true }),
  })
end

-- bufferline.nvim
local bufferline_config = function()
  require('bufferline').setup({
    options = {
      mode = 'tabs',
      hover = {
        enabled = true,
        delay = 200,
        reveal = { 'close' }
      },
      diagnostics = 'nvim_lsp',
      diagnostics_indicator = function(count, level)
        local icon = level:match("error") and " " or ""
        return ' ' .. icon .. count
      end
    }
  })
end

-- gina.vim
local gina_config = function()
  local gina_keymaps = {
    { map = 'nmap', buffer = 'status', lhs = 'gp', rhs = '<Cmd>terminal git push<CR>' },
    { map = 'nmap', buffer = 'status', lhs = 'gr', rhs = '<Cmd>terminal gh pr create -d<CR>' },
    { map = 'nmap', buffer = 'status', lhs = 'gl', rhs = '<Cmd>terminal git pull<CR>' },
    { map = 'nmap', buffer = 'status', lhs = 'cm', rhs = '<Cmd>Gina commit<CR>' },
    { map = 'nmap', buffer = 'status', lhs = 'ca', rhs = '<Cmd>Gina commit --amend<CR>' },
    { map = 'nmap', buffer = 'status', lhs = 'dp', rhs = '<Plug>(gina-patch-oneside-tab)' },
    { map = 'nmap', buffer = 'status', lhs = 'ga', rhs = '--' },
    { map = 'vmap', buffer = 'status', lhs = 'ga', rhs = '--' },
    { map = 'nmap', buffer = 'log', lhs = 'dd', rhs = '<Plug>(gina-changes-of)' },
    { map = 'nmap', buffer = 'branch', lhs = 'n', rhs = '<Plug>(gina-branch-new)' },
    { map = 'nmap', buffer = 'branch', lhs = 'D', rhs = '<Plug>(gina-branch-delete)' },
    { map = 'nmap', buffer = '/.*', lhs = 'q', rhs = '<Cmd>bw<CR>' },
  }
  for _, m in pairs(gina_keymaps) do
    vim.fn['gina#custom#mapping#' .. m.map](m.buffer, m.lhs, m.rhs, { silent = true })
  end

  vim.fn['gina#custom#command#option']('log', '--opener', 'new')
  vim.fn['gina#custom#command#option']('status', '--opener', 'new')
  vim.fn['gina#custom#command#option']('branch', '--opener', 'new')
  nmap('gs', '<Cmd>Gina status<CR>')
  nmap('gl', '<Cmd>Gina log<CR>')
  nmap('gm', '<Cmd>Gina glame<CR>')
  nmap('gb', '<Cmd>Gina branch<CR>')
  nmap('gu', ':Gina browse --exact --yank :<CR>')
  vmap('gu', ':Gina browse --exact --yank :<CR>')
end

-- telescope.vim
local telescope_config = function()
  nmap('<C-p>', '<Cmd>Telescope find_files<CR>')
  nmap('mg', '<Cmd>Telescope live_grep<CR>')
  nmap('md', '<Cmd>Telescope diagnostics<CR>')
  nmap('mf', '<Cmd>Telescope current_buffer_fuzzy_find<CR>')

  require('telescope').setup {
    pickers = {
      find_files = {
        mappings = {
          i = {
            ['<C-j>'] = 'move_selection_next',
            ['<C-k>'] = 'move_selection_previous',
            ['<C-s>'] = 'select_horizontal',
            ['<C-v>'] = 'select_vertical',
            ['<C-t>'] = 'select_tab',
            ['<C-e>'] = 'select_drop',
          }
        }
      }
    }
  }
end

-- fern.vim
local fern_config = function()
  vim.g['fern#renderer'] = 'nerdfont'
  vim.g['fern#window_selector_use_popup'] = true
  vim.g['fern#default_hidden'] = 1
  vim.g['fern#default_exclude'] = '.git$'

  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'fern',
    callback = function()
      nmap('q', ':q<CR>', { silent = true, buffer = true })
      nmap('<C-x>', '<Plug>(fern-action-open:split)', { silent = true, buffer = true })
      nmap('<C-v>', '<Plug>(fern-action-open:vsplit)', { silent = true, buffer = true })
      nmap('<C-t>', '<Plug>(fern-action-tcd)', { silent = true, buffer = true })
    end,
    group = vim.api.nvim_create_augroup('fernInit', { clear = true }),
  })

  nmap('<Leader>f', ':Fern . -drawer<CR>')
end

-- lsp config
local lsp_config = function()
  require('mason-lspconfig').setup({
    automatic_installation = {
      exclude = {
        'gopls',
        'denols',
      }
    }
  })

  local lspconfig = require("lspconfig")

  local ls = {
    -- 'sumneko_lua',
    -- 'tsserver',
    -- 'denols',
    'golangci_lint_ls',
    'eslint',
    'graphql',
    'bashls',
    'yamlls',
    'gopls',
    'jsonls',
    'vimls',
  }

  for _, s in pairs(ls) do
    lspconfig[s].setup({
      on_attach = Lsp_on_attach
    })
  end

  lspconfig.denols.setup({
    root_dir = lspconfig.util.root_pattern('deps.ts', 'deno.json', 'import_map.json', '.git'),
    init_options = {
      lint = true,
      unstable = true
    },
    on_attach = Lsp_on_attach,
  })

  lspconfig.tsserver.setup({
    root_dir = lspconfig.util.root_pattern('package.json', 'node_modules'),
    on_attach = Lsp_on_attach,
  })

  lspconfig.sumneko_lua.setup({
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
          library = vim.api.nvim_get_runtime_file("", true),
        },
      },
    },
    on_attach = Lsp_on_attach,
  })
end

-- treesitter config
local treesitter_config = function()
  require('nvim-treesitter.configs').setup({
    ensure_installed = {
      'lua', 'rust', 'typescript', 'tsx',
      'go', 'gomod', 'sql', 'toml', 'yaml',
      'html', 'javascript', 'graphql',
      'markdown', 'markdown_inline'
    },
    auto_install = true,
    highlight = {
      enable = true,
    }
  })
end

-- gitsigns.nvim
local gitsigns_config = function()
  require('gitsigns').setup({
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
      map({ 'n', 'x' }, 'g]', ':Gitsigns stage_hunk<CR>', opts)
      map({ 'n', 'x' }, 'g[', ':Gitsigns undo_stage_hunk<CR>', opts)
      map({ 'o', 'x' }, 'ih', ':<C-U>Gitsigns select_hunk<CR>', opts)
      map({ 'n', 'x' }, 'mp', ':Gitsigns preview_hunk<CR>', opts)
    end
  })
end

-- plugin settings
local ensure_packer = function()
  local install_path = vim.fn.stdpath('data') .. '/site/pack/packer/start/packer.nvim'
  if vim.fn.empty(vim.fn.glob(install_path)) == 1 then
    vim.fn.system({ 'git', 'clone', '--depth', '1', 'https://github.com/wbthomason/packer.nvim', install_path })
    vim.cmd('packadd packer.nvim')
    return true
  end
  return false
end

local packer_bootstrap = ensure_packer()

require('packer').startup(function(use)
  use { 'wbthomason/packer.nvim' }

  use {
    'pwntester/octo.nvim',
    requires = {
      'nvim-lua/plenary.nvim',
      'nvim-telescope/telescope.nvim',
      'kyazdani42/nvim-web-devicons',
    },
    config = function()
      require('octo').setup()
    end
  }

  -- lsp_signature
  use {
    'ray-x/lsp_signature.nvim',
    config = function()
      require('lsp_signature').setup({})
    end
  }

  -- git signs
  use {
    'lewis6991/gitsigns.nvim',
    config = gitsigns_config
  }

  -- status line
  use {
    'nvim-lualine/lualine.nvim',
    requires = 'kyazdani42/nvim-web-devicons',
    config = function()
      require('lualine').setup({})
    end
  }

  -- tabpage
  use {
    'akinsho/bufferline.nvim',
    tag = "v2.*",
    requires = 'kyazdani42/nvim-web-devicons',
    config = bufferline_config
  }

  -- colorscheme
  use {
    'cocopon/iceberg.vim',
    config = iceberg_config,
  }
  use {
    'nvim-treesitter/nvim-treesitter',
    run = ':TSUpdate',
    config = treesitter_config
  }

  -- better quickfix
  use { 'kevinhwang91/nvim-bqf', ft = 'qf' }

  -- lsp
  use {
    'williamboman/mason-lspconfig.nvim',
    requires = {
      { 'neovim/nvim-lspconfig' },
      {
        'williamboman/mason.nvim',
        config = function() require("mason").setup() end,
      },
    },
    config = lsp_config,
  }

  use {
    'j-hui/fidget.nvim',
    config = function() require('fidget').setup() end,
  }

  use {
    'kkharji/lspsaga.nvim',
    config = function()
      require('lspsaga').setup({
        error_sign = '💩',
        warn_sign = '🦍',
        hint_sign = "",
        infor_sign = "",
      })
    end,
  }

  -- complete
  use {
    'hrsh7th/nvim-cmp',
    requires = {
      'hrsh7th/cmp-nvim-lsp',
      'hrsh7th/cmp-buffer',
      'hrsh7th/cmp-path',
      'hrsh7th/cmp-vsnip',
      'hrsh7th/vim-vsnip',
    },
    config = nvim_cmp_config,
  }

  -- for development
  use {
    'windwp/nvim-autopairs',
    config = function()
      require("nvim-autopairs").setup({ map_c_h = true })
    end,
  }

  use 'vim-test/vim-test'
  use {
    'lambdalisue/fern.vim',
    branch = 'main',
    requires = {
      { 'lambdalisue/fern-hijack.vim' },
      { 'lambdalisue/nerdfont.vim' },
      { 'lambdalisue/fern-renderer-nerdfont.vim' }
    },
    config = fern_config,
  }
  use {
    'lambdalisue/gina.vim',
    config = gina_config,
  }
  use 'lambdalisue/guise.vim'
  use 'mattn/emmet-vim'
  use 'mattn/vim-sonictemplate'
  use 'simeji/winresizer'
  use 'vim-denops/denops.vim'
  use 'skanehira/denops-silicon.vim'
  use 'skanehira/denops-docker.vim'
  use {
    'thinca/vim-quickrun',
    requires = {
      { 'skanehira/quickrun-neoterm.vim', opt = true }
    }
  }
  use 'tyru/open-browser-github.vim'
  use 'tyru/open-browser.vim'
  use 'mattn/vim-goimports'
  use 'skanehira/denops-graphql.vim'
  use 'thinca/vim-prettyprint'
  use 'skanehira/k8s.vim'
  use 'skanehira/winselector.vim'
  use {
    'nvim-telescope/telescope.nvim',
    requires = { { 'nvim-lua/plenary.nvim' } },
    config = telescope_config,
  }
  use {
    'simrat39/rust-tools.nvim',
    config = rust_tools_config,
  }

  -- for documentation
  use 'glidenote/memolist.vim'
  use 'godlygeek/tabular'
  use 'gyim/vim-boxdraw'
  use 'mattn/vim-maketable'
  use 'shinespark/vim-list2tree'
  use 'skanehira/gyazo.vim'
  use 'skanehira/denops-translate.vim'
  use 'vim-jp/vimdoc-ja'
  use 'plasticboy/vim-markdown'
  use 'previm/previm'

  -- for develop vim plugins
  use 'LeafCage/vimhelpgenerator'
  use 'lambdalisue/vital-Whisky'
  use 'tweekmonster/helpful.vim'
  use 'vim-jp/vital.vim'
  use 'thinca/vim-themis'
  use 'tyru/capture.vim'

  -- other
  use 'skanehira/denops-twihi.vim'

  if packer_bootstrap then
    require('packer').sync()
  end
end)

-- update config when install, clean, update the plugins
vim.api.nvim_create_autocmd('User', {
  pattern = 'PackerComplete',
  command = 'PackerCompile',
  group = vim.api.nvim_create_augroup('packerComplete', { clear = true }),
})

-- options
vim.cmd('syntax enable')
vim.cmd('filetype plugin indent on')

vim.g.mapleader = " "
vim.opt.breakindent = true
vim.opt.number = false
vim.opt.incsearch = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.hlsearch = true
vim.opt.smartindent = true
vim.opt.virtualedit = "block"
vim.opt.showtabline = 1
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.softtabstop = 2
vim.opt.completeopt = 'menu,menuone,noselect'
vim.opt.laststatus = 3
vim.opt.scrolloff = 100
vim.opt.cursorline = true
vim.opt.helplang = 'ja'
vim.opt.autowrite = true
vim.opt.swapfile = false
vim.opt.showtabline = 1
vim.opt.diffopt = 'vertical'
vim.opt.wildcharm = ('<Tab>'):byte()
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.softtabstop = 2
vim.opt.expandtab = true
vim.opt.clipboard:append({ vim.fn.has('mac') == true and 'unnamed' or 'unnamedplus' })
vim.opt.grepprg = 'rg --vimgrep'
vim.opt.mouse = {}

-- file indent
local filetype_indent_group = vim.api.nvim_create_augroup('fileTypeIndent', { clear = true })
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
    pattern = { 'javascript', 'typescriptreact', 'typescript', 'vim', 'lua', 'yaml', 'json', 'sh', 'zsh', 'markdown' },
    command = 'setlocal tabstop=2 softtabstop=2 shiftwidth=2 expandtab'
  },
}

for _, indent in pairs(file_indents) do
  vim.api.nvim_create_autocmd('FileType', {
    pattern = indent.pattern,
    command = indent.command,
    group = filetype_indent_group
  })
end

-- grep window
vim.api.nvim_create_autocmd('QuickFixCmdPost', {
  pattern = '*grep*',
  command = 'cwindow',
  group = vim.api.nvim_create_augroup('grepWindow', { clear = true }),
})

-- restore cursorline
vim.api.nvim_create_autocmd('BufReadPost',
  {
    pattern = '*',
    callback = function()
      vim.cmd([[
    if line("'\"") > 0 && line("'\"") <= line("$")
      exe "normal! g'\""
    endif
    ]] )
    end,
    group = vim.api.nvim_create_augroup('restoreCursorline', { clear = true })
  })

-- persistent undo
local ensure_undo_dir = function()
  local undo_path = vim.fn.expand('~/.config/nvim/undo')
  if vim.fn.isdirectory(undo_path) == 0 then
    vim.fn.mkdir(undo_path, 'p')
  end
  vim.opt.undodir = undo_path
  vim.opt.undofile = true
end
ensure_undo_dir()

-- start insert mode when termopen
vim.api.nvim_create_autocmd("TermOpen", {
  pattern = "*",
  command = "startinsert",
  group = vim.api.nvim_create_augroup("neovimTerminal", { clear = true }),
})

-- auto mkdir
local auto_mkdir = function(dir)
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, 'p')
  end
end
vim.api.nvim_create_autocmd('BufWritePre', {
  pattern = '*',
  callback = function()
    auto_mkdir(vim.fn.expand('<afile>:p:h'))
  end,
  group = vim.api.nvim_create_augroup('autoMkdir', { clear = true })
})

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

-- help
vim.api.nvim_create_autocmd("FileType", {
  pattern = "help",
  command = "nnoremap <buffer> <silent>q :bw!<CR>",
  group = vim.api.nvim_create_augroup("helpKeymaps", { clear = true }),
})

-- command line
-- cmap defaults silent to true, but passes an empty setting because the cursor is not updated
cmap('<C-b>', '<Left>', {})
cmap('<C-f>', '<Right>', {})
cmap('<C-a>', '<Home>', {})
cmap('<Up>', '<C-p>')
cmap('<Down>', '<C-n>')
cmap('<C-n>', function()
  return vim.fn.pumvisible() == 1 and '<C-n>' or '<Down>'
end, { expr = true })
cmap('<C-p>', function()
  return vim.fn.pumvisible() == 1 and '<C-p>' or '<Up>'
end, { expr = true })
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'qf',
  callback = function()
    nmap('q', '<Cmd>q<CR>', { silent = true, buffer = true })
  end,
  group = vim.api.nvim_create_augroup("qfInit", { clear = true }),
})

-- paste with <C-v>
local paste_rhs = 'printf("<C-r><C-o>%s", v:register)'
map({ 'c', 'i' }, '<C-v>', paste_rhs, { expr = true })

-- other keymap
nmap('ms', function()
  vim.cmd([[
  luafile ~/.config/nvim/init.lua
  PackerInstall
  ]])
end)
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

-- translate.vim
nmap('gr', '<Plug>(Translate)')
vmap('gr', '<Plug>(Translate)')

-- quickrun.vim
vim.g['quickrun_config'] = {
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
  rust = {
    command = 'cargo',
    exec = '%C run --quiet %s %a',
  },
}

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'quickrun',
  callback = function()
    nmap('q', '<Cmd>bw!<CR>', { silent = true, buffer = true })
  end,
  group = vim.api.nvim_create_augroup('quickrunInit', { clear = true }),
})

-- vim-markdown
vim.g['vim_markdown_folding_disabled'] = true

-- emmet
vim.g['emmet_html5'] = false
vim.g['user_emmet_install_global'] = false
vim.g['user_emmet_settings'] = {
  variables = {
    lang = 'ja'
  }
}
vim.g['user_emmet_leader_key'] = '<C-g>'
vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'vue', 'html', 'css', 'typescriptreact' },
  command = 'EmmetInstall',
  group = vim.api.nvim_create_augroup("emmetInstall", { clear = true }),
})

-- vim-sonictemplate.vim
vim.g['sonictemplate_author'] = 'skanehira'
vim.g['sonictemplate_license'] = 'MIT'
vim.g['sonictemplate_vim_template_dir'] = vim.fn.expand('~/.vim/sonictemplate')
imap('<C-l>', '<plug>(sonictemplate-postfix)', { silent = true })

-- vimhelpgenerator
vim.g['vimhelpgenerator_version'] = ''
vim.g['vimhelpgenerator_author'] = 'Author: skanehira <sho19921005@gmail.com>'
vim.g['vimhelpgenerator_uri'] = 'https://github.com/skanehira/'
vim.g['vimhelpgenerator_defaultlanguage'] = 'en'

-- gyazo.vim
vim.g['gyazo_insert_markdown'] = true
nmap('gup', '<Plug>(gyazo-upload)')

-- winselector.vim
nmap('<C-f>', '<Plug>(winselector)')

-- change visual highlight
vim.cmd('hi Visual ctermfg=159 ctermbg=23 guifg=#b3c3cc guibg=#384851')

-- test.vim
vim.g['test#javascript#denotest#options'] = { all = '--parallel --unstable -A' }
nmap('<Leader>tn', '<Cmd>TestNearest<CR>', { silent = true })

-- open-browser.vim
nmap('gop', '<Plug>(openbrowser-open)')

-- create zenn article
vim.api.nvim_create_user_command('ZennCreateArticle',
  function(opts)
    local date = vim.fn.strftime('%Y-%m-%d')
    local slug = date .. '-' .. opts.args
    local cmd = 'npx zenn new:article --emoji 🦍 --slug ' .. slug
    os.execute(cmd)
    vim.cmd('edit ' .. string.format('articles/%s.md', slug))
  end, { nargs = 1 })

-- insert markdown link
local insert_markdown_link = function()
  local old = vim.fn.getreg(9)
  local link = vim.fn.trim(vim.fn.getreg())
  print(link:match('^http.*'))
  if link:match('^http.*') == nil then
    vim.cmd('normal! p')
    return
  end
  vim.cmd('normal! "9y')
  local word = vim.fn.getreg(9)
  local text = string.format('[%s](%s)', word, link)
  vim.fn.setreg(9, text)
  vim.cmd('normal! gv"9p')
  vim.fn.setreg(9, old)
end

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'markdown',
  callback = function()
    map('x', 'p', function()
      insert_markdown_link()
    end, { silent = true, buffer = true })
  end,
  group = vim.api.nvim_create_augroup("markdownInsertLink", { clear = true }),
})

-- graphql.vim
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'graphql',
  callback = function()
    nmap('gp', '<Plug>(graphql-execute)')
  end,
  group = vim.api.nvim_create_augroup("graphqlInit", { clear = true }),
})

-- twihi.vim
vim.g['twihi_mention_check_interval'] = 30000 * 10
vim.g['twihi_notify_ui'] = 'system'

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

local twihi_init_group = vim.api.nvim_create_augroup("twihiInit", { clear = true })
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'twihi-timeline',
  callback = function()
    twihi_timeline_keymap()
  end,
  group = twihi_init_group,
})

vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'twihi-reply', 'twihi-tweet', 'twihi-retweet' },
  callback = function()
    twihi_media_keymap()
  end,
  group = twihi_init_group,
})

-- silicon.vim
vim.g['silicon_options'] = {
  font = 'Hack Nerd Font',
  no_line_number = true,
  background_color = '#434C5E',
  no_window_controls = true,
  theme = 'Nord',
}

nmap('gi', '<Plug>(silicon-generate)')
xmap('gi', '<Plug>(silicon-generate)')

-- k8s.vim
local k8s_pods_keymap = function()
  nmap('<CR>', '<Plug>(k8s:pods:containers)', { buffer = true })
  nmap('<C-g><C-l>', '<Plug>(k8s:pods:logs)', { buffer = true })
  nmap('<C-g><C-d>', '<Plug>(k8s:pods:describe)', { buffer = true })
  nmap('D', '<Plug>(k8s:pods:delete)', { buffer = true })
  nmap('K', '<Plug>(k8s:pods:kill)', { buffer = true })
  nmap('<C-g><C-y>', '<Plug>(k8s:pods:yaml)', { buffer = true })
  nmap('<C-e>', '<Plug>(k8s:pods:events)', { buffer = true })
  nmap('s', '<Plug>(k8s:pods:shell)', { buffer = true })
  nmap('e', '<Plug>(k8s:pods:exec)', { buffer = true })
  nmap('E', '<Plug>(k8s:pods:edit)', { buffer = true })
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
  { ft = 'k8s-pods', fn = k8s_pods_keymap },
  { ft = 'k8s-nodes', fn = k8s_nodes_keymap },
  { ft = 'k8s-containers', fn = k8s_containers_keymap },
  { ft = 'k8s-deployments', fn = k8s_deployments_keymap },
  { ft = 'k8s-services', fn = k8s_services_keymap },
  { ft = 'k8s-secrets', fn = k8s_secrets_keymap },
}

local k8s_keymap_group = vim.api.nvim_create_augroup("k8sInit", { clear = true })

for _, m in pairs(k8s_keymaps) do
  vim.api.nvim_create_autocmd('FileType', {
    pattern = m.ft,
    callback = m.fn,
    group = k8s_keymap_group,
  })
end
