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

for i = 1, #disable_plugins do
  vim.g[disable_plugins[i]] = true
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
      ['<C-e>'] = cmp.mapping.confirm({ select = true }),
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
local lsp_on_attach = function(client, bufnr)
  -- Enable completion triggered by <c-x><c-o>
  vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')
  local bufopts = { silent = true, buffer = bufnr }
  vim.keymap.set('n', 'K', vim.lsp.buf.hover, bufopts)
  vim.keymap.set('n', '<Leader>gi', vim.lsp.buf.implementation, bufopts)
  vim.keymap.set('n', '<Leader>gr', vim.lsp.buf.references, bufopts)
  vim.keymap.set('n', '<Leader>rn', vim.lsp.buf.rename, bufopts)
  vim.keymap.set('n', '<C-]>', vim.lsp.buf.definition, bufopts)
  vim.keymap.set('n', 'ga', vim.lsp.buf.code_action, bufopts)
  vim.keymap.set('n', '<Leader>gl', vim.lsp.codelens.run, bufopts)

  -- auto format when save the file
  local augroup = vim.api.nvim_create_augroup("LspFormatting", {})
  if client.supports_method("textDocument/formatting") then
    vim.keymap.set('n', 'mf', vim.lsp.buf.format, { buffer = bufnr })
    vim.api.nvim_clear_autocmds({ group = augroup, buffer = bufnr })
    vim.api.nvim_create_autocmd("BufWritePre", {
      group = augroup,
      buffer = bufnr,
      callback = function()
        vim.lsp.buf.format()
      end,
    })
  end
end

-- rust-tools.nvim
local rust_tools_config = function()
  local rt = require("rust-tools")
  rt.setup({
    server = {
      on_attach = function(client, bufnr)
        -- Hover actions
        local bufopts = { silent = true, buffer = bufnr }
        vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')
        vim.keymap.set('n', 'K', rt.hover_actions.hover_actions, bufopts)
        vim.keymap.set('n', '<Leader>gi', vim.lsp.buf.implementation, bufopts)
        vim.keymap.set('n', '<Leader>gr', vim.lsp.buf.references, bufopts)
        vim.keymap.set('n', '<Leader>rn', vim.lsp.buf.rename, bufopts)
        vim.keymap.set('n', '<C-]>', vim.lsp.buf.definition, bufopts)
        vim.keymap.set('n', 'ga', vim.lsp.buf.code_action, bufopts)
        vim.keymap.set('n', '<Leader>gl', rt.code_action_group.code_action_group, bufopts)

        -- auto format when save the file
        local augroup = vim.api.nvim_create_augroup("LspFormatting", {})
        if client.supports_method("textDocument/formatting") then
          vim.keymap.set('n', 'mf', vim.lsp.buf.format)
          vim.api.nvim_clear_autocmds({ group = augroup, buffer = bufnr })
          vim.api.nvim_create_autocmd("BufWritePre", {
            group = augroup,
            buffer = bufnr,
            callback = function()
              vim.lsp.buf.format()
            end,
          })
        end
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

-- lightline.vim
local lightline_config = function()
  vim.cmd([[
function! FilePath()
  if winwidth(0) > 90
    return expand("%:s")
  else
    return expand("%:t")
  endif
endfunction
]] )

  vim.g.lightline = {
    colorscheme = 'iceberg',
    active = {
      left = { { 'mode', 'paste' }, { 'readonly', 'branchName', 'filepath', 'modified' } },
    },
    component_function = {
      filepath = 'FilePath',
    },
  }
end

-- gina.vim
local gina_config = function()
  local gina_keymaps = {
    { map = 'nmap', buffer = 'status', lhs = 'gp', rhs = '<Cmd>terminal git push<CR>', opt = { silent = true } },
    { map = 'nmap', buffer = 'status', lhs = 'gr', rhs = '<Cmd>terminal gh pr create -d<CR>', opt = { silent = true } },
    { map = 'nmap', buffer = 'status', lhs = 'gl', rhs = '<Cmd>terminal git pull<CR>', opt = { silent = true } },
    { map = 'nmap', buffer = 'status', lhs = 'cm', rhs = '<Cmd>Gina commit<CR>', opt = { silent = true } },
    { map = 'nmap', buffer = 'status', lhs = 'ca', rhs = '<Cmd>Gina commit --amend<CR>', opt = { silent = true } },
    { map = 'nmap', buffer = 'status', lhs = 'dp', rhs = '<Plug>(gina-patch-oneside-tab)', opt = { silent = true } },
    { map = 'nmap', buffer = 'status', lhs = 'ga', rhs = '--', opt = { silent = true } },
    { map = 'vmap', buffer = 'status', lhs = 'ga', rhs = '--', opt = { silent = true } },
    { map = 'nmap', buffer = 'log', lhs = 'dd', rhs = '<Plug>(gina-changes-of)', opt = { silent = true } },
    { map = 'nmap', buffer = 'branch', lhs = 'n', rhs = '<Plug>(gina-branch-new)', opt = { silent = true } },
    { map = 'nmap', buffer = 'branch', lhs = 'D', rhs = '<Plug>(gina-branch-delete)', opt = { silent = true } },
    { map = 'nmap', buffer = '/.*', lhs = 'q', rhs = '<Cmd>bw<CR>', opt = { silent = true } },
  }
  for i = 1, #gina_keymaps do
    local m = gina_keymaps[i]
    vim.fn['gina#custom#mapping#' .. m.map](m.buffer, m.lhs, m.rhs, m.opt)
  end

  vim.fn['gina#custom#command#option']('log', '--opener', 'new')
  vim.fn['gina#custom#command#option']('status', '--opener', 'new')
  vim.fn['gina#custom#command#option']('branch', '--opener', 'new')
  vim.keymap.set('n', 'gs', '<Cmd>Gina status<CR>')
  vim.keymap.set('n', 'gl', '<Cmd>Gina log<CR>')
  vim.keymap.set('n', 'gm', '<Cmd>Gina glame<CR>')
  vim.keymap.set('n', 'gb', '<Cmd>Gina branch<CR>')
  vim.keymap.set('n', 'gu', '<Cmd>Gina browse --exact --yank :<CR>')
  vim.keymap.set('v', 'gu', '<Cmd>Gina browse --exact --yank :<CR>')
end

-- telescope.vim
local telescope_config = function()
  vim.keymap.set('n', '<C-p>', '<Cmd>Telescope find_files<CR>')
  vim.keymap.set('n', '<C-g><C-g>', '<Cmd>Telescope grep_string<CR>')

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
      vim.keymap.set('n', 'q', ':q<CR>', { silent = true, buffer = true })
      vim.keymap.set('n', '<C-x>', '<Plug>(fern-action-open:split)', { silent = true, buffer = true })
      vim.keymap.set('n', '<C-v>', '<Plug>(fern-action-open:vsplit)', { silent = true, buffer = true })
      vim.keymap.set('n', '<C-t>', '<Plug>(fern-action-tcd)', { silent = true, buffer = true })
    end,
    group = vim.api.nvim_create_augroup('fernInit', { clear = true }),
  })

  vim.keymap.set('n', '<Leader>f', ':Fern . -drawer<CR>', { silent = true })
end

-- plugin settings
local ensure_packer = function()
  local install_path = vim.fn.stdpath('data') .. '/site/pack/packer/start/packer.nvim'
  if vim.fn.empty(vim.fn.glob(install_path)) == 1 then
    vim.fn.system({ 'git', 'clone', '--depth', '1', 'https://github.com/wbthomason/packer.nvim', install_path })
    vim.cmd [[packadd packer.nvim]]
    return true
  end
  return false
end

local packer_bootstrap = ensure_packer()

require('packer').startup(function(use)
  use 'wbthomason/packer.nvim'

  -- colorscheme
  use {
    'cocopon/iceberg.vim',
    config = iceberg_config,
  }
  use {
    'itchyny/lightline.vim',
    config = lightline_config,
  }

  -- lsp
  use {
    'williamboman/mason-lspconfig.nvim',
    requires = {
      { 'neovim/nvim-lspconfig' },
      {
        'williamboman/mason.nvim',
        config = function() require("mason").setup() end,
      },
    }
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
      'hrsh7th/vim-vsnip-integ',
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
  use 'kshenoy/vim-signature'
  use 'vim-test/vim-test'
  use {
    'lambdalisue/fern.vim',
    branch = 'main',
    requires = {
      { 'lambdalisue/fern-hijack.vim' },
      { 'lambdalisue/fern-git-status.vim' },
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

-- lsp config
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

for i = 1, #ls do
  lspconfig[ls[i]].setup({
    on_attach = lsp_on_attach
  })
end

lspconfig.denols.setup({
  root_dir = lspconfig.util.root_pattern('deps.ts', 'deno.json', 'import_map.json'),
  init_options = {
    lint = true,
    unstable = true
  },
  on_attach = lsp_on_attach,
})

lspconfig.tsserver.setup({
  root_dir = lspconfig.util.root_pattern('package.json', 'node_modules'),
  on_attach = lsp_on_attach,
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
  on_attach = lsp_on_attach,
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
vim.opt.winbar = "%#MoreMsg#%f%m"
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

for i = 1, #file_indents do
  local indent = file_indents[i]
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
vim.keymap.set('o', '8', 'i(')
vim.keymap.set('o', '2', 'i"')
vim.keymap.set('o', '7', 'i\'')
vim.keymap.set('o', '@', 'i`')
vim.keymap.set('o', '[', 'i[')
vim.keymap.set('o', '{', 'i{')
vim.keymap.set('o', 'a8', 'a(')
vim.keymap.set('o', 'a2', 'a"')
vim.keymap.set('o', 'a7', 'a\'')
vim.keymap.set('o', 'a@', 'a`')

vim.keymap.set('n', 'v8', 'vi(')
vim.keymap.set('n', 'v2', 'vi"')
vim.keymap.set('n', 'v7', 'vi\'')
vim.keymap.set('n', 'v@', 'vi`')
vim.keymap.set('n', 'v[', 'vi[')
vim.keymap.set('n', 'v{', 'vi{')
vim.keymap.set('n', 'va8', 'va(')
vim.keymap.set('n', 'va2', 'va"')
vim.keymap.set('n', 'va7', 'va\'')
vim.keymap.set('n', 'va@', 'va`')

-- emacs like
vim.keymap.set('i', '<C-k>', '<C-o>C')
vim.keymap.set('i', '<C-f>', '<Right>')
vim.keymap.set('i', '<C-b>', '<Left>')
vim.keymap.set('i', '<C-e>', '<C-o>A')
vim.keymap.set('i', '<C-a>', '<C-o>I')

-- help
vim.api.nvim_create_autocmd("FileType", {
  pattern = "help",
  command = "nnoremap <buffer> <silent>q :bw!<CR>",
  group = vim.api.nvim_create_augroup("helpKeymaps", { clear = true }),
})

-- command line
vim.keymap.set('c', '<C-b>', '<Left>')
vim.keymap.set('c', '<C-f>', '<Right>')
vim.keymap.set('c', '<C-a>', '<Home>')

-- paste with <C-v>
local paste_rhs = 'printf("<C-r><C-o>%s", v:register)'
vim.keymap.set('i', '<C-v>', paste_rhs, { expr = true })
vim.keymap.set('c', '<C-v>', paste_rhs, { expr = true })

-- other keymap
vim.keymap.set('n', 'ms', function()
  vim.cmd([[
  luafile ~/.config/nvim/init.lua
  PackerCompile
  ]])
end)
vim.keymap.set('n', 'Y', 'Y')
vim.keymap.set('n', 'R', 'gR')
vim.keymap.set('n', '*', '*N')
vim.keymap.set('n', '<Esc><Esc>', '<Cmd>nohlsearch<CR>')
vim.keymap.set('n', 'H', '^')
vim.keymap.set('n', 'L', 'g_')
vim.keymap.set('v', 'H', '^')
vim.keymap.set('v', 'L', 'g_')
vim.keymap.set('n', '<C-j>', 'o<Esc>')
vim.keymap.set('n', '<C-k>', 'O<Esc>')
vim.keymap.set('n', 'o', 'A<CR>')
vim.keymap.set('n', '<C-l>', 'gt')
vim.keymap.set('n', '<C-h>', 'gT')
vim.keymap.set('t', '<C-]>', [[<C-\><C-n>]])
vim.keymap.set('n', '<Leader>tm', [[:new | terminal<CR>]])
vim.keymap.set('c', '<Up>', '<C-p>')
vim.keymap.set('c', '<Down>', '<C-n>')
vim.keymap.set('c', '<C-n>', function()
  return vim.fn.pumvisible() == 1 and '<C-n>' or '<Down>'
end, { expr = true })
vim.keymap.set('c', '<C-p>', function()
  return vim.fn.pumvisible() == 1 and '<C-p>' or '<Up>'
end, { expr = true })

-- translate.vim
vim.keymap.set('n', 'gr', '<Plug>(Translate)')
vim.keymap.set('v', 'gr', '<Plug>(Translate)')

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
    vim.keymap.set('n', 'q', '<Cmd>bw!<CR>', { silent = true, buffer = true })
  end,
  group = vim.api.nvim_create_augroup('quickrunInit', { clear = true }),
})

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
vim.keymap.set('i', '<C-l>', '<plug>(sonictemplate-postfix)', { silent = true })

-- vimhelpgenerator
vim.g['vimhelpgenerator_version'] = ''
vim.g['vimhelpgenerator_author'] = 'Author: skanehira <sho19921005@gmail.com>'
vim.g['vimhelpgenerator_uri'] = 'https://github.com/skanehira/'
vim.g['vimhelpgenerator_defaultlanguage'] = 'en'

-- gyazo.vim
vim.g['gyazo_insert_markdown'] = true
vim.keymap.set('n', 'gup', '<Plug>(gyazo-upload)')

-- winselector.vim
vim.keymap.set('n', '<C-f>', '<Plug>(winselector)')

-- change visual highlight
vim.cmd('hi Visual ctermfg=159 ctermbg=23 guifg=#b3c3cc guibg=#384851')

-- test.vim
vim.g['test#javascript#denotest#options'] = { all = '--parallel --unstable -A' }
vim.keymap.set('n', '<Leader>tn', '<Cmd>TestNearest<CR>', { silent = true })

-- open-browser.vim
vim.keymap.set('n', 'gop', '<Plug>(openbrowser-open)')

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
  if string.match(link, '^http.*') == '' then
    vim.cmd('normal! gvp')
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
    vim.keymap.set('x', 'p', function()
      insert_markdown_link()
    end, { silent = true, buffer = true })
  end,
  group = vim.api.nvim_create_augroup("markdownInsertLink", { clear = true }),
})

-- graphql.vim
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'graphql',
  callback = function()
    vim.keymap.set('n', 'gp', '<Plug>(graphql-execute)', { buffer = true })
  end,
  group = vim.api.nvim_create_augroup("graphqlInit", { clear = true }),
})

-- twihi.vim
vim.g['twihi_mention_check_interval'] = 30000 * 10
vim.g['twihi_notify_ui'] = 'system'

vim.keymap.set('n', '<C-g>n', '<Cmd>TwihiTweet<CR>', { silent = true })
vim.keymap.set('n', '<C-g>m', '<Cmd>TwihiMentions<CR>', { silent = true })
vim.keymap.set('n', '<C-g>h', '<Cmd>TwihiHome<CR>', { silent = true })

local twihi_timeline_keymap = function()
  vim.keymap.set('n', '<C-g><C-y>', '<Plug>(twihi:tweet:yank)', { buffer = true, silent = true })
  vim.keymap.set('n', 'R', '<Plug>(twihi:retweet)', { buffer = true, silent = true })
  vim.keymap.set('n', '<C-g><C-l>', '<C-g><C-l> <Plug>(twihi:tweet:like)', { buffer = true, silent = true })
  vim.keymap.set('n', '<C-o>', '<Plug>(twihi:tweet:open)', { buffer = true, silent = true })
  vim.keymap.set('n', '<C-r>', '<Plug>(twihi:reply)', { buffer = true, silent = true })
  vim.keymap.set('n', '<C-j>', '<Plug>(twihi:tweet:next)', { buffer = true, silent = true })
  vim.keymap.set('n', '<C-k>', '<Plug>(twihi:tweet:prev)', { buffer = true, silent = true })
end

local twihi_media_keymap = function()
  vim.keymap.set('n', '<C-g>m', '<Plug>(twihi:media:add:clipboard)', { buffer = true, silent = true })
  vim.keymap.set('n', '<C-g>d', '<Plug>(twihi:media:remove)', { buffer = true, silent = true })
  vim.keymap.set('n', '<C-g>o', '<Plug>(twihi:media:open)', { buffer = true, silent = true })
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
  no_line_number = true,
  background_color = '#434C5E',
  no_window_controls = true,
  theme = 'Nord',
}

vim.keymap.set('n', 'gi', '<Plug>(silicon-generate)', { silent = true })
vim.keymap.set('x', 'gi', '<Plug>(silicon-generate)', { silent = true })

-- k8s.vim
local k8s_pods_keymap = function()
  vim.keymap.set('n', '<CR>', '<Plug>(k8s:pods:containers)', { buffer = true })
  vim.keymap.set('n', '<C-g><C-l>', '<Plug>(k8s:pods:logs)', { buffer = true })
  vim.keymap.set('n', '<C-g><C-d>', '<Plug>(k8s:pods:describe)', { buffer = true })
  vim.keymap.set('n', 'D', '<Plug>(k8s:pods:delete)', { buffer = true })
  vim.keymap.set('n', 'K', '<Plug>(k8s:pods:kill)', { buffer = true })
  vim.keymap.set('n', '<C-g><C-y>', '<Plug>(k8s:pods:yaml)', { buffer = true })
  vim.keymap.set('n', '<C-e>', '<Plug>(k8s:pods:events)', { buffer = true })
  vim.keymap.set('n', 's', '<Plug>(k8s:pods:shell)', { buffer = true })
  vim.keymap.set('n', 'e', '<Plug>(k8s:pods:exec)', { buffer = true })
  vim.keymap.set('n', 'E', '<Plug>(k8s:pods:edit)', { buffer = true })
end

local k8s_nodes_keymap = function()
  vim.keymap.set('n', '<C-g><C-d>', '<Plug>(k8s:nodes:describe)', { buffer = true })
  vim.keymap.set('n', '<C-g><C-y>', '<Plug>(k8s:nodes:yaml)', { buffer = true })
  vim.keymap.set('n', '<CR>', '<Plug>(k8s:nodes:pods)', { buffer = true })
  vim.keymap.set('n', 'E', '<Plug>(k8s:nodes:edit)', { buffer = true })
end

local k8s_containers_keymap = function()
  vim.keymap.set('n', 's', '<Plug>(k8s:pods:containers:shell)', { buffer = true })
  vim.keymap.set('n', 'e', '<Plug>(k8s:pods:containers:exec)', { buffer = true })
end

local k8s_deployments_keymap = function()
  vim.keymap.set('n', '<C-g><C-d>', '<Plug>(k8s:deployments:describe)', { buffer = true })
  vim.keymap.set('n', '<C-g><C-y>', '<Plug>(k8s:deployments:yaml)', { buffer = true })
  vim.keymap.set('n', 'E', '<Plug>(k8s:deployments:edit)', { buffer = true })
  vim.keymap.set('n', '<CR>', '<Plug>(k8s:deployments:pods)', { buffer = true })
  vim.keymap.set('n', 'D', '<Plug>(k8s:deployments:delete)', { buffer = true })
end

local k8s_services_keymap = function()
  vim.keymap.set('n', '<CR>', '<Plug>(k8s:svcs:pods)', { buffer = true })
  vim.keymap.set('n', '<C-g><C-d>', '<Plug>(k8s:svcs:describe)', { buffer = true })
  vim.keymap.set('n', 'D', '<Plug>(k8s:svcs:delete)', { buffer = true })
  vim.keymap.set('n', '<C-g><C-y>', '<Plug>(k8s:svcs:yaml)', { buffer = true })
  vim.keymap.set('n', 'E', '<Plug>(k8s:svcs:edit)', { buffer = true })
end

local k8s_secrets_keymap = function()
  vim.keymap.set('n', '<C-g><C-d>', '<Plug>(k8s:secrets:describe)', { buffer = true })
  vim.keymap.set('n', '<C-g><C-y>', '<Plug>(k8s:secrets:yaml)', { buffer = true })
  vim.keymap.set('n', 'E', '<Plug>(k8s:secrets:edit)', { buffer = true })
  vim.keymap.set('n', 'D', '<Plug>(k8s:secrets:delete)', { buffer = true })
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

for i = 1, #k8s_keymaps do
  local m = k8s_keymaps[i]
  vim.api.nvim_create_autocmd('FileType', {
    pattern = m.ft,
    callback = m.fn,
    group = k8s_keymap_group,
  })
end
