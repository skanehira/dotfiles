-- 編集バッファ管理の高レベルAPI
-- コールバック駆動の設計で、バッファ操作とイベントハンドリングを分離

local M = {}

-- バッファの全内容を取得
-- @param bufnr number バッファ番号
-- @return string バッファの全テキスト（改行で結合）
function M.get_buffer_content(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return table.concat(lines, "\n")
end

-- バッファを閉じる
-- @param bufnr number バッファ番号
function M.close_buffer(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end


-- バッファローカルキーマップを設定
-- @param bufnr number バッファ番号
-- @param config table コールバック設定
local function setup_keymaps(bufnr, config)
  local opts = { buffer = bufnr, noremap = true, silent = true }

  -- <CR>: ノーマルモードでEnterキーを押してテキストを送信し、バッファをクリア
  -- コメントスタック方式では「コメントを保存してフロートを閉じる」セマンティクスになる
  if config.on_submit then
    vim.keymap.set("n", "<CR>", function()
      local content = M.get_buffer_content(bufnr)
      config.on_submit(content, bufnr)
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
      end
    end, vim.tbl_extend("force", opts, { desc = "Submit and clear buffer" }))
  end

  -- <C-s>: スタックを経由せず即送信（バックドア）
  if config.on_submit_immediate then
    local immediate = function()
      local content = M.get_buffer_content(bufnr)
      config.on_submit_immediate(content, bufnr)
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
      end
    end
    vim.keymap.set("n", "<C-s>", immediate,
      vim.tbl_extend("force", opts, { desc = "Submit immediately (bypass comment stack)" }))
    vim.keymap.set("i", "<C-s>", function()
      vim.cmd("stopinsert")
      immediate()
    end, vim.tbl_extend("force", opts, { desc = "Submit immediately (bypass comment stack)" }))
  end

  -- q: ウィンドウだけ閉じる（バッファは保持）
  vim.keymap.set("n", "q", function()
    local win = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, vim.tbl_extend("force", opts, { desc = "Close float window" }))

  -- tmuxペインへの単純パススルー keymap 群
  -- { mode = キーマップモード, key = キー, cb = config のコールバック名, desc = キーマップ説明 }
  local passthrough_keymaps = {
    { mode = "n", key = "<C-x><C-x>", cb = "on_interrupt",          desc = "Interrupt process in tmux pane" },
    { mode = "n", key = "<C-d>",      cb = "on_scroll_down",        desc = "Send PageDown to tmux pane" },
    { mode = "n", key = "<C-u>",      cb = "on_scroll_up",          desc = "Send PageUp to tmux pane" },
    { mode = "n", key = "<C-e>",      cb = "on_send_ctrl_e",        desc = "Send Ctrl+E to tmux pane" },
    { mode = "n", key = "<C-a>",      cb = "on_send_ctrl_a",        desc = "Send Ctrl+A to tmux pane" },
    { mode = "n", key = "<C-f>",      cb = "on_send_ctrl_f",        desc = "Send Ctrl+F to tmux pane" },
    { mode = "n", key = "<C-b>",      cb = "on_send_ctrl_b",        desc = "Send Ctrl+B to tmux pane" },
    { mode = "n", key = "<C-h>",      cb = "on_send_ctrl_h",        desc = "Send Ctrl+H to tmux pane" },
    { mode = "n", key = "<C-g><C-b>", cb = "on_scroll_to_bottom",   desc = "Send Ctrl+End to tmux pane (jump to bottom)" },
    { mode = "n", key = "<Tab>",      cb = "on_send_tab",           desc = "Send Tab to tmux pane" },
    { mode = "n", key = "<S-Tab>",    cb = "on_send_shift_tab",     desc = "Send Shift+Tab to tmux pane" },
    { mode = "n", key = "<Space>",    cb = "on_send_space",         desc = "Send Space to tmux pane" },
    { mode = "n", key = "<C-c>",      cb = "on_send_ctrl_c",        desc = "Send C-c to tmux pane" },
    { mode = "n", key = "<Esc>",      cb = "on_send_escape",        desc = "Send Escape to tmux pane" },
    { mode = "n", key = "R",          cb = "on_send_double_escape", desc = "Send Escape x2 to tmux pane (rewind)" },
    { mode = "n", key = "<Up>",       cb = "on_send_up",            desc = "Send Up to tmux pane" },
    { mode = "n", key = "<C-p>",      cb = "on_send_up",            desc = "Send Up to tmux pane" },
    { mode = "n", key = "<Down>",     cb = "on_send_down",          desc = "Send Down to tmux pane" },
    { mode = "n", key = "<C-n>",      cb = "on_send_down",          desc = "Send Down to tmux pane" },
    { mode = "n", key = "<Left>",     cb = "on_send_left",          desc = "Send Left to tmux pane" },
    { mode = "n", key = "<Right>",    cb = "on_send_right",         desc = "Send Right to tmux pane" },
    { mode = "i", key = "<C-v>",      cb = "on_send_ctrl_v",        desc = "Send Ctrl+V to tmux pane" },
  }
  -- ループ変数の closure キャプチャを避けるため factory で生成
  local function make_passthrough(cb_name)
    return function() config[cb_name]() end
  end
  for _, m in ipairs(passthrough_keymaps) do
    if config[m.cb] then
      vim.keymap.set(m.mode, m.key, make_passthrough(m.cb),
        vim.tbl_extend("force", opts, { desc = m.desc }))
    end
  end

  -- <C-r>: ファイル検索（telescope）
  local complete = require("modules.ai.complete")
  vim.keymap.set("i", "<C-r>", function()
    complete.pick_file()
  end, vim.tbl_extend("force", opts, { desc = "Search and insert file path" }))

  -- <C-l>: コマンド・スキル検索（telescope）
  vim.keymap.set("i", "<C-l>", function()
    complete.pick_command()
  end, vim.tbl_extend("force", opts, { desc = "Search and insert command/skill" }))
end

-- バッファ名でバッファを検索
-- @param name string バッファ名
-- @return number|nil バッファ番号、見つからない場合はnil
local function find_buffer_by_name(name)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local buf_name = vim.b[buf].ai_buffer_name
      if buf_name == name then
        return buf
      end
    end
  end
  return nil
end

-- バッファが表示されているウィンドウを検索
-- @param bufnr number バッファ番号
-- @return number|nil ウィンドウID、見つからない場合はnil
local function find_window_with_buffer(bufnr)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      return win
    end
  end
  return nil
end

-- フローティングウィンドウでバッファを開く
-- @param bufnr number バッファ番号
-- @param title string|nil ウィンドウタイトル
local function open_buffer_in_float_window(bufnr, title)
  local width = math.min(math.floor(vim.o.columns * 0.8), 120)
  local height = 10
  local row = math.floor((vim.o.lines - height - 2) / 2)
  local col = math.floor((vim.o.columns - width - 2) / 2)

  local opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    border = "rounded",
  }

  if title then
    opts.title = " " .. title .. " "
    opts.title_pos = "center"
  end

  local win = vim.api.nvim_open_win(bufnr, true, opts)
  vim.wo[win].winhighlight = "Normal:Normal,FloatBorder:FloatBorder"
end

-- 入力用バッファを作成または既存のものを表示
-- @param config table 設定テーブル
--   - name: string バッファ名（例: "[Claude Input]"）
--   - filetype: string ファイルタイプ（例: "markdown"）
--   - on_submit: function(content, bufnr) テキスト送信時のコールバック
--   - on_scroll_down: function() 下スクロール時のコールバック
--   - on_scroll_up: function() 上スクロール時のコールバック
--   - on_scroll_to_bottom: function() 最下部へジャンプ時のコールバック
--   - on_interrupt: function() プロセス割り込み時のコールバック
--   - on_send_shift_tab: function() Shift+Tab送信時のコールバック
-- @return number 作成/再利用されたバッファ番号
function M.create_input_buffer(config)
  -- 既存のバッファを探す
  local existing_bufnr = config.name and find_buffer_by_name(config.name) or nil

  if existing_bufnr then
    -- 既存のバッファが見つかった場合
    local win = find_window_with_buffer(existing_bufnr)
    if win then
      -- ウィンドウに表示されている場合はフォーカス
      vim.api.nvim_set_current_win(win)
    else
      -- ウィンドウに表示されていない場合は新しいfloatで開く
      open_buffer_in_float_window(existing_bufnr, config.name)
    end
    vim.cmd("startinsert")
    return existing_bufnr
  end

  -- 新しいバッファを作成
  local bufnr = vim.api.nvim_create_buf(false, true)

  -- バッファオプションを設定
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false

  if config.filetype then
    vim.bo[bufnr].filetype = config.filetype
  end

  if config.name then
    vim.b[bufnr].ai_buffer_name = config.name
  end

  -- フローティングウィンドウでバッファを開く
  open_buffer_in_float_window(bufnr, config.name)

  -- キーマップを設定（新しいバッファの場合のみ）
  setup_keymaps(bufnr, config)

  vim.cmd("startinsert")

  return bufnr
end

return M
