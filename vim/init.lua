---@diagnostic disable: redundant-parameter

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

-- lsp global settings
require('my/lsp')

-- keymaps
local keymaps = require('my/keymaps')
local map = keymaps.map
local nmap = keymaps.nmap
local xmap = keymaps.xmap
local vmap = keymaps.vmap

-- options
require('my/options')

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
    ]])
    end,
    group = vim.api.nvim_create_augroup('restoreCursorline', { clear = true })
  })

-- start insert mode when termopen
vim.api.nvim_create_autocmd("TermOpen", {
  pattern = "*",
  callback = function()
    vim.cmd('startinsert')
    vim.cmd('setlocal scrolloff=0')
  end,
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

-- create zenn article
vim.api.nvim_create_user_command('ZennCreateArticle',
  function(opts)
    local date = vim.fn.strftime('%Y-%m-%d')
    local slug = date .. '-' .. opts.args
    os.execute('npx zenn new:article --emoji 🦍 --slug ' .. slug)
    vim.cmd('edit ' .. string.format('articles/%s.md', slug))
  end, { nargs = 1 })

-- insert markdown link
local insert_markdown_link = function()
  local old = vim.fn.getreg('9')
  local link = vim.fn.trim(vim.fn.getreg())
  if link:match('^http.*') == nil then
    vim.cmd('normal! p')
    return
  end
  vim.cmd('normal! "9y')
  local word = vim.fn.getreg('9')
  local text = string.format('[%s](%s)', word, link)
  vim.fn.setreg('9', text)
  vim.cmd('normal! gv"9p')
  vim.fn.setreg('9', old)
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

--- syntax clear
-- vim.api.nvim_create_autocmd('FileType', {
--   pattern = {'go', 'vim', 'javascript', 'typescript', 'rust', 'json'},
--   callback = function ()
--     vim.cmd('syntax clear')
--   end
-- })

-- help
vim.api.nvim_create_autocmd("FileType", {
  pattern = "help",
  command = "nnoremap <buffer> <silent>q :bw!<CR>",
  group = vim.api.nvim_create_augroup("helpKeymaps", { clear = true }),
})

-- ############################# plugin config section ###############################

-- lsp on attach
Lsp_on_attach = function(client, bufnr)
  -- Enable completion triggered by <c-x><c-o>
  client.server_capabilities.semanticTokensProvider = nil
  vim.api.nvim_set_option_value('omnifunc', 'v:lua.vim.lsp.omnifunc', {
    buf = bufnr
  })
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
          vim.fn.jobstart({ 'open', url })
        end
      end)
  end, bufopts)
  nmap('<C-g><C-d>', vim.diagnostic.open_float, bufopts)
  if client.name == 'denols' then
    nmap('<C-]>', vim.lsp.buf.definition, bufopts)
  else
    vim.opt.tagfunc = 'v:lua.vim.lsp.tagfunc'
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

  -- local augroup = vim.api.nvim_create_augroup("LspFormatting", { clear = false })
  -- if client.supports_method("textDocument/formatting") then
  --   nmap(']f', vim.lsp.buf.format, { buffer = bufnr })
  --   if client.name == 'sumneko_lua' then
  --     return
  --   end
  --   vim.api.nvim_create_autocmd("BufWritePre", {
  --     callback = function()
  --       organize_import()
  --       vim.lsp.buf.format()
  --     end,
  --     group = augroup,
  --     buffer = bufnr,
  --   })
  -- end
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

-- silicon.vim
vim.g['silicon_options'] = {
  font = 'Cica',
  no_line_number = true,
  -- background_color = '#434C5E',
  no_window_controls = true,
  theme = 'GitHub',
}

local denops_config = function()
  vim.g['denops#server#deno_args'] = {
    '-q',
    '--no-lock',
    '-A',
    '--unstable-ffi'
  }
end

local silicon_config = function()
  nmap('gi', '<Plug>(silicon-generate)')
  xmap('gi', '<Plug>(silicon-generate)')
end

-- graphql.vim
local graphql_config = function()
  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'graphql',
    callback = function()
      nmap('gp', '<Plug>(graphql-execute)')
    end,
    group = vim.api.nvim_create_augroup("graphqlInit", { clear = true }),
  })
end

-- translate.vim
local translate_config = function()
  nmap('gr', '<Plug>(Translate)')
  vmap('gr', '<Plug>(Translate)')
end

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
  ['rust/cargo'] = {
    command = 'cargo',
    exec = '%C run --quiet %s %a',
  },
}

local quickrun_config = function()
  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'quickrun',
    callback = function()
      nmap('q', '<Cmd>bw!<CR>', { silent = true, buffer = true })
    end,
    group = vim.api.nvim_create_augroup('quickrunInit', { clear = true }),
  })
end

-- vim-markdown
vim.g['vim_markdown_folding_disabled'] = true

-- emmet

-- vimhelpgenerator
vim.g['vimhelpgenerator_version'] = ''
vim.g['vimhelpgenerator_author'] = 'Author: skanehira <sho19921005@gmail.com>'
vim.g['vimhelpgenerator_uri'] = 'https://github.com/skanehira/'
vim.g['vimhelpgenerator_defaultlanguage'] = 'en'

-- gyazo.vim
vim.g['gyazo_insert_markdown'] = true
local gyazo_config = function()
  nmap('gup', '<Plug>(gyazo-upload)')
end

-- open-browser.vim
local openbrowser_config = function()
  nmap('gop', '<Plug>(openbrowser-open)')
end

-- ############################# lazy config section ###############################
-- lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

---@diagnostic disable-next-line: undefined-field
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end
---@diagnostic disable-next-line: undefined-field
vim.opt.rtp:prepend(lazypath)

-- lazy settings
require("lazy").setup({
  require('my/plugins/kensaku'),
  require('my/plugins/treesitter'),
  require('my/plugins/skkeleton'),

  -- window
  require('my/plugins/window/zoom'),
  require('my/plugins/window/winresizer'),
  require('my/plugins/window/winselector'),

  -- completion
  require('my/plugins/completion/nvim-cmp'),
  require('my/plugins/completion/nvim-autopairs'),
  require('my/plugins/completion/sonictemplate'),
  require('my/plugins/completion/emmet'),
  require('my/plugins/completion/copilot'),

  -- filer
  require('my/plugins/filer/fern'),
  require('my/plugins/filer/fern-renderer-nerdfont'),

  -- lsp
  require('my/plugins/lsp/fidget'),
  require('my/plugins/lsp/null-ls'),
  require('my/plugins/lsp/lsp_signature'),
  require('my/plugins/lsp/lsp_lines'),
  require('my/plugins/lsp/mason'),

  -- git
  require('my/plugins/git/gitsigns'),
  require('my/plugins/git/gina'),

  -- languages
  require('my/plugins/lang/rust/crates'),
  require('my/plugins/lang/go/goimports'),

  -- quickfix
  require('my/plugins/quickfix/qfreplace'),
  require('my/plugins/quickfix/bqf'),

  -- statusline
  require('my/plugins/statusline/lualine'),
  require('my/plugins/statusline/bufferline'),

  -- colorscheme
  require('my/plugins/colorscheme/nightfox'),

  -- testing
  require('my/plugins/testing'),

  -- infra
  require('my/plugins/infra/k8s'),

  {
    'lambdalisue/guise.vim',
  },
  {
    'vim-denops/denops.vim',
    config = denops_config,
  },
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
      ---@diagnostic disable-next-line: missing-fields
      require('hlchunk').setup({
        ---@diagnostic disable-next-line: missing-fields
        blank = {
          enable = false,
        }
      })
    end
  },
})
