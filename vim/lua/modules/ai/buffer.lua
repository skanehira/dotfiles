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
    vim.keymap.set("n", "<C-x>", function()
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
end

-- バッファ名でバッファを検索
-- @param name string バッファ名
-- @return number|nil バッファ番号、見つからない場合はnil
local function find_buffer_by_name(name)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local buf_name = vim.api.nvim_buf_get_name(buf)
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
end

-- 入力用バッファを作成または既存のものを表示
-- @param config table 設定テーブル
--   - name: string バッファ名（例: "[Claude Input]"）
--   - filetype: string ファイルタイプ（例: "markdown"）
--   - on_submit: function(content, bufnr) テキスト送信時のコールバック
--   - on_scroll_down: function() 下スクロール時のコールバック
--   - on_scroll_up: function() 上スクロール時のコールバック
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
      -- ウィンドウに表示されていない場合は新しいウィンドウで開く
      open_buffer_in_new_window(existing_bufnr)
    end
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
    vim.api.nvim_buf_set_name(bufnr, config.name)
  end

  -- 新しいウィンドウを作成してバッファを開く
  open_buffer_in_new_window(bufnr)

  -- キーマップを設定（新しいバッファの場合のみ）
  setup_keymaps(bufnr, config)

  return bufnr
end

return M
