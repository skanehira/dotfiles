local utils = require('utils')
local vmap = utils.keymaps.vmap
local nmap = utils.keymaps.nmap

-- gin-status の 2 文字ステータスコード (XY) を見て stage/unstage をトグルする。
-- worktree 側 (Y) に変更があれば stage、staged のみなら unstage する。
local function toggle_stage()
  local line = vim.api.nvim_get_current_line()
  local code = line:sub(1, 2)
  if code == '' or code:match('^##') then
    return
  end
  local y = code:sub(2, 2)
  local plug = y ~= ' ' and '<Plug>(gin-action-stage)' or '<Plug>(gin-action-unstage)'
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(plug, true, false, true), 'm', false)
end

local gin_config = function()
  vim.g.gin_status_persistent_args = { '++opener=new' }
  vim.g.gin_log_persistent_args = { '++opener=new' }
  vim.g.gin_branch_persistent_args = { '++opener=new' }
  vim.g.gin_proxy_apply_without_confirm = true

  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'gin-status',
    callback = function(ev)
      local opts = { buffer = ev.buf, silent = true }
      vim.keymap.set('n', 'gp', '<Cmd>Gin push<CR>', opts)
      vim.keymap.set('n', 'gr', '<Cmd>terminal gh pr create<CR>', opts)
      vim.keymap.set('n', 'gl', '<Cmd>Gin pull<CR>', opts)
      vim.keymap.set('n', 'cm', '<Cmd>Gin commit<CR>', opts)
      vim.keymap.set('n', 'ca', '<Cmd>Gin commit --amend<CR>', opts)
      vim.keymap.set('n', 'dp', '<Plug>(gin-action-patch:worktree)', opts)
      vim.keymap.set('n', 'gc', '<Plug>(gin-action-chaperon)', opts)
      vim.keymap.set('n', 'ga', toggle_stage, opts)
      vim.keymap.set('v', 'ga', toggle_stage, opts)
    end,
  })

  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'gin-log',
    callback = function(ev)
      vim.keymap.set('n', 'dd', '<Plug>(gin-action-show)', { buffer = ev.buf, silent = true })
    end,
  })

  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'gin-branch',
    callback = function(ev)
      local opts = { buffer = ev.buf, silent = true }
      vim.keymap.set('n', 'n', '<Plug>(gin-action-new)', opts)
      vim.keymap.set('n', 'D', '<Plug>(gin-action-delete)', opts)
      vim.keymap.set('n', 'p', '<Cmd>terminal gh pr create<CR>', opts)
    end,
  })

  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'gin-*',
    callback = function(ev)
      vim.keymap.set('n', 'q', '<Cmd>bd<CR>', { buffer = ev.buf, silent = true })
    end,
  })

  -- gin が開く一覧バッファはジャンプリストに正しいカーソル行が乗らないため
  -- (dd で diff を開いた時のエントリが line=1 になる)、離脱時に view を保存し
  -- 再入時に復元する
  local saved_views = {}

  vim.api.nvim_create_autocmd('BufLeave', {
    pattern = { 'ginstatus://*', 'ginlog://*', 'ginbranch://*' },
    callback = function(ev)
      saved_views[ev.buf] = vim.fn.winsaveview()
    end,
  })

  vim.api.nvim_create_autocmd('BufEnter', {
    pattern = { 'ginstatus://*', 'ginlog://*', 'ginbranch://*' },
    callback = function(ev)
      local view = saved_views[ev.buf]
      if view then
        -- <C-o> 等のジャンプは BufEnter 後にカーソルを配置するため、
        -- schedule でジャンプ完了後に復元する
        vim.schedule(function()
          if vim.api.nvim_get_current_buf() == ev.buf then
            vim.fn.winrestview(view)
          end
        end)
      end
    end,
  })

  -- gin は status/branch/log 等のバッファを開くたびに bufnr を埋め込んだ
  -- autocmd グループ (GinCommandPost / BufWritePost → gin#util#reload(bufnr))
  -- を登録するが、バッファが wipe されてもグループを掃除しない。
  -- 残骸グループが後続の git 操作で発火すると E680 (invalid buffer number)
  -- になるため、wipe 時にグループを削除する。
  vim.api.nvim_create_autocmd('BufWipeout', {
    pattern = {
      'ginstatus://*',
      'ginbranch://*',
      'ginlog://*',
      'gintag://*',
      'ginreflog://*',
      'ginstash://*',
    },
    callback = function(ev)
      pcall(vim.api.nvim_del_augroup_by_name, 'gin_core_echo_command_bind_' .. ev.buf)
      pcall(vim.api.nvim_del_augroup_by_name, 'gin_command_status_command_read_' .. ev.buf)
      saved_views[ev.buf] = nil
    end,
  })

  nmap('gs', '<Cmd>GinStatus<CR>')
  nmap('gl', '<Cmd>GinLog<CR>')
  nmap('gm', '<Cmd>GinBlame %<CR>')
  nmap('gb', '<Cmd>GinBranch<CR>')
  nmap('gu', '<Cmd>GinBrowse ++yank --permalink --no-browser<CR>')
  vmap('gu', ':GinBrowse ++yank --permalink --no-browser<CR>')
end

local gin = {
  'lambdalisue/vim-gin',
  dependencies = { 'vim-denops/denops.vim' },
  config = gin_config,
}

return gin
