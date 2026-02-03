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

-- バッファの内容をクリアする
-- @param bufnr number バッファ番号
function M.clear_buffer(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
  end
end

-- バッファローカルキーマップを設定
-- @param bufnr number バッファ番号
-- @param config table コールバック設定
local function setup_keymaps(bufnr, config)
  local opts = { buffer = bufnr, noremap = true, silent = true }

  -- <CR>: ノーマルモードでEnterキーを押してテキストを送信
  if config.on_submit then
    vim.keymap.set("n", "<CR>", function()
      local content = M.get_buffer_content(bufnr)
      config.on_submit(content, bufnr)
    end, vim.tbl_extend("force", opts, { desc = "Submit and close buffer" }))
  end

  -- q: バッファを閉じる（変更がある場合は閉じない）
  vim.keymap.set("n", "q", function()
    local modified = vim.bo[bufnr].modified
    if modified then
      vim.notify("No write since last change (add ! to override)", vim.log.levels.WARN)
    else
      M.close_buffer(bufnr)
    end
  end, vim.tbl_extend("force", opts, { desc = "Close buffer" }))

  -- <C-x>: ペインで動いているプロセスを終了
  if config.on_interrupt then
    vim.keymap.set("n", "<C-x><C-x>", function()
      config.on_interrupt()
    end, vim.tbl_extend("force", opts, { desc = "Interrupt process in tmux pane" }))
  end

  -- <C-d>: tmuxペインを下にスクロール
  if config.on_scroll_down then
    vim.keymap.set("n", "<C-d>", function()
      config.on_scroll_down()
    end, vim.tbl_extend("force", opts, { desc = "Scroll tmux pane down" }))
  end

  -- <C-u>: tmuxペインを上にスクロール
  if config.on_scroll_up then
    vim.keymap.set("n", "<C-u>", function()
      config.on_scroll_up()
    end, vim.tbl_extend("force", opts, { desc = "Scroll tmux pane up" }))
  end

  -- <C-n>: tmuxペインを1行下にスクロール
  if config.on_scroll_line_down then
    vim.keymap.set("n", "<C-n>", function()
      config.on_scroll_line_down()
    end, vim.tbl_extend("force", opts, { desc = "Scroll tmux pane down 1 line" }))
  end

  -- <C-p>: tmuxペインを1行上にスクロール
  if config.on_scroll_line_up then
    vim.keymap.set("n", "<C-p>", function()
      config.on_scroll_line_up()
    end, vim.tbl_extend("force", opts, { desc = "Scroll tmux pane up 1 line" }))
  end

  -- <Tab>: Tabをtmux側に送信
  if config.on_send_tab then
    vim.keymap.set("n", "<Tab>", function()
      config.on_send_tab()
    end, vim.tbl_extend("force", opts, { desc = "Send Tab to tmux pane" }))
  end

  -- <S-Tab>: Shift+Tabをtmux側に送信
  if config.on_send_shift_tab then
    vim.keymap.set("n", "<S-Tab>", function()
      config.on_send_shift_tab()
    end, vim.tbl_extend("force", opts, { desc = "Send Shift+Tab to tmux pane" }))
  end

  -- <Space>: スペースをtmux側に送信
  if config.on_send_space then
    vim.keymap.set("n", "<Space>", function()
      config.on_send_space()
    end, vim.tbl_extend("force", opts, { desc = "Send Space to tmux pane" }))
  end

  -- <C-c>: コピーモードを終了
  if config.on_exit_copy_mode then
    vim.keymap.set("n", "<C-c>", function()
      config.on_exit_copy_mode()
    end, vim.tbl_extend("force", opts, { desc = "Exit tmux copy mode" }))
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

  -- <C-v>: Ctrl+Vをtmux側に送信
  if config.on_send_ctrl_v then
    vim.keymap.set("i", "<C-v>", function()
      config.on_send_ctrl_v()
    end, vim.tbl_extend("force", opts, { desc = "Send Ctrl+V to tmux pane" }))
  end

  -- <Up>: 上矢印をtmux側に送信
  if config.on_send_up then
    vim.keymap.set("n", "<Up>", function()
      config.on_send_up()
    end, vim.tbl_extend("force", opts, { desc = "Send Up to tmux pane" }))
  end

  -- <Down>: 下矢印をtmux側に送信
  if config.on_send_down then
    vim.keymap.set("n", "<Down>", function()
      config.on_send_down()
    end, vim.tbl_extend("force", opts, { desc = "Send Down to tmux pane" }))
  end

  -- <Left>: 左矢印をtmux側に送信
  if config.on_send_left then
    vim.keymap.set("n", "<Left>", function()
      config.on_send_left()
    end, vim.tbl_extend("force", opts, { desc = "Send Left to tmux pane" }))
  end

  -- <Right>: 右矢印をtmux側に送信
  if config.on_send_right then
    vim.keymap.set("n", "<Right>", function()
      config.on_send_right()
    end, vim.tbl_extend("force", opts, { desc = "Send Right to tmux pane" }))
  end
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

-- 新しいウィンドウでバッファを開く（高さは画面の1/4）
-- @param bufnr number バッファ番号
local function open_buffer_in_new_window(bufnr)
  local height = math.floor(vim.o.lines / 10)
  vim.cmd(string.format("%dnew", height))
  vim.api.nvim_set_current_buf(bufnr)

  -- ウィンドウの高さを固定
  local win = vim.api.nvim_get_current_win()
  vim.wo[win].winfixheight = true
end

-- 入力用バッファを作成または既存のものを表示
-- @param config table 設定テーブル
--   - name: string バッファ名（例: "[Claude Input]"）
--   - filetype: string ファイルタイプ（例: "markdown"）
--   - on_submit: function(content, bufnr) テキスト送信時のコールバック
--   - on_scroll_down: function() 下スクロール時のコールバック
--   - on_scroll_up: function() 上スクロール時のコールバック
--   - on_interrupt: function() プロセス割り込み時のコールバック
--   - on_scroll_line_down: function() 1行下スクロール時のコールバック
--   - on_scroll_line_up: function() 1行上スクロール時のコールバック
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
      -- ウィンドウの高さを固定（念のため再設定）
      vim.wo[win].winfixheight = true
    else
      -- ウィンドウに表示されていない場合は新しいウィンドウで開く
      open_buffer_in_new_window(existing_bufnr)
    end
    -- インサートモードで開始
    vim.cmd("startinsert")
    return existing_bufnr
  end

  -- 新しいバッファを作成
  local bufnr = vim.api.nvim_create_buf(false, true)

  -- バッファオプションを設定
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false

  if config.filetype then
    vim.bo[bufnr].filetype = config.filetype
  end

  if config.name then
    vim.b[bufnr].ai_buffer_name = config.name
  end

  -- 新しいウィンドウを作成してバッファを開く
  open_buffer_in_new_window(bufnr)

  -- キーマップを設定（新しいバッファの場合のみ）
  setup_keymaps(bufnr, config)

  -- インサートモードで開始
  vim.cmd("startinsert")

  return bufnr
end

return M
