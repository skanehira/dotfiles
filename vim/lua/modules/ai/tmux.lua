-- tmux操作の低レベルAPI
-- このモジュールは外部状態を持たず、純粋にtmuxコマンドのラッパーとして機能する

local M = {}

-- tmuxセッション内で実行されているかチェック
-- @return boolean tmuxセッション内ならtrue
function M.is_in_tmux()
  return vim.env.TMUX ~= nil and vim.env.TMUX ~= ""
end

-- tmuxコマンドを実行してエラーハンドリング
-- @param cmd string tmuxコマンド
-- @return string|nil, string|nil 成功時は (出力, nil)、失敗時は (nil, エラーメッセージ)
local function exec_tmux(cmd)
  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    local error_msg = string.format(
      "tmux command failed (exit code: %d)\nCommand: %s\nOutput: %s",
      vim.v.shell_error,
      cmd,
      vim.trim(result)
    )
    return nil, error_msg
  end
  return vim.trim(result), nil
end

-- 新規ペインを作成（現在のペインを縦分割）
-- @param size_percent number 新規ペインのサイズ（%）
-- @param shell_command string|nil 実行するコマンド（省略時は通常のシェル）
-- @return string|nil, string|nil 成功時は (ペインID, nil)、失敗時は (nil, エラーメッセージ)
function M.create_pane(size_percent, shell_command)
  -- -h: 横方向に分割（縦配置）
  -- -d: 新しいペインに切り替えない（detached）
  -- -l: サイズ指定（%を付けるとパーセンテージ）
  -- -P: ペインIDを標準出力に表示
  -- -F: 出力フォーマット指定（#{pane_id}で%形式のIDを取得）
  local cmd
  if shell_command then
    -- コマンドを指定する場合は、シングルクォートでエスケープ
    local escaped_cmd = shell_command:gsub("'", "'\\''")
    cmd = string.format("tmux split-window -dh -l %d%% -P -F '#{pane_id}' '%s'", size_percent, escaped_cmd)
  else
    cmd = string.format("tmux split-window -dh -l %d%% -P -F '#{pane_id}'", size_percent)
  end

  local output, err = exec_tmux(cmd)
  if not output then
    return nil, err
  end

  -- 出力からペインIDを抽出（例: "%2"）
  local pane_id = vim.trim(output)
  if not pane_id:match("^%%[0-9]+$") then
    return nil, "Failed to parse pane ID from output: " .. output
  end

  return pane_id, nil
end

-- ペインが存在するかチェック
-- @param pane_id string ペインID（例: "%2"）
-- @return boolean 存在すればtrue
function M.pane_exists(pane_id)
  local cmd = string.format("tmux list-panes -a -F '#{pane_id}'")
  local result, _ = exec_tmux(cmd)
  if not result then
    return false
  end

  for _, line in ipairs(vim.split(result, "\n")) do
    if vim.trim(line) == pane_id then
      return true
    end
  end
  return false
end

-- 現在のウィンドウ内で特定のコマンドを実行しているペインを検索
-- @param pattern string コマンド名のパターン（部分一致）
-- @return string|nil ペインID、見つからない場合はnil
function M.find_pane_by_command(pattern)
  -- pane_start_commandを使ってペイン起動時のコマンドを取得
  -- pane_current_commandは実行中プロセス名になるため不正確
  -- -aなし: 現在のウィンドウ内のペインのみを検索
  local cmd = "tmux list-panes -F '#{pane_id}:#{pane_start_command}'"
  local result, _ = exec_tmux(cmd)
  if not result then
    return nil
  end

  for _, line in ipairs(vim.split(result, "\n")) do
    local pane_id, command = line:match("^([^:]+):(.+)$")
    if pane_id and command and command:find(pattern, 1, true) then
      return pane_id
    end
  end
  return nil
end

-- ペインにキーを送信
-- @param pane_id string ペインID
-- @param keys string 送信するキー（例: "C-c", "Enter"）
-- @return boolean, string|nil 成功時は (true, nil)、失敗時は (false, エラーメッセージ)
function M.send_keys(pane_id, keys)
  local cmd = string.format("tmux send-keys -t %s %s", pane_id, keys)
  local _, err = exec_tmux(cmd)
  if err then
    return false, err
  end
  return true, nil
end

-- ペインにテキストを送信（リテラルモード）
-- @param pane_id string ペインID
-- @param text string 送信するテキスト
-- @return boolean, string|nil 成功時は (true, nil)、失敗時は (false, エラーメッセージ)
function M.send_text(pane_id, text)
  -- -l: リテラルモード（特殊キーとして解釈しない）
  -- --: オプションの終わりを明示（-で始まるテキストをフラグとして解釈させない）
  -- テキストをシングルクォートでエスケープ
  local escaped = text:gsub("'", "'\\''")
  local cmd = string.format("tmux send-keys -t %s -l -- '%s'", pane_id, escaped)
  local _, err = exec_tmux(cmd)
  if err then
    return false, err
  end

  -- Enterキーを送信してコマンド実行
  return M.send_keys(pane_id, "Enter")
end

-- ペインをスクロール（ハーフページ単位）
-- @param pane_id string ペインID
-- @param direction string "up" または "down"
-- @param lines number スクロールする行数（デフォルト: ハーフページ）
-- @return boolean, string|nil 成功時は (true, nil)、失敗時は (false, エラーメッセージ)
function M.scroll(pane_id, direction, lines)
  -- コピーモードに入ってスクロール
  local scroll_cmd
  if direction == "up" then
    scroll_cmd = lines and string.format("halfpage-up -N %d", lines) or "halfpage-up"
  elseif direction == "down" then
    scroll_cmd = lines and string.format("halfpage-down -N %d", lines) or "halfpage-down"
  else
    return false, "Invalid direction: must be 'up' or 'down'"
  end

  -- コピーモードに入ってスクロール、その後コピーモードを抜ける
  local cmd = string.format(
    "tmux copy-mode -t %s && tmux send-keys -t %s -X %s",
    pane_id,
    pane_id,
    scroll_cmd
  )

  local _, err = exec_tmux(cmd)
  if err then
    return false, err
  end
  return true, nil
end

-- ペインを1行ずつスクロール
-- @param pane_id string ペインID
-- @param direction string "up" または "down"
-- @return boolean, string|nil 成功時は (true, nil)、失敗時は (false, エラーメッセージ)
function M.scroll_line(pane_id, direction)
  local scroll_cmd
  if direction == "up" then
    scroll_cmd = "scroll-up"
  elseif direction == "down" then
    scroll_cmd = "scroll-down"
  else
    return false, "Invalid direction: must be 'up' or 'down'"
  end

  -- コピーモードに入って1行スクロール
  local cmd = string.format(
    "tmux copy-mode -t %s && tmux send-keys -t %s -X %s",
    pane_id,
    pane_id,
    scroll_cmd
  )

  local _, err = exec_tmux(cmd)
  if err then
    return false, err
  end
  return true, nil
end

-- 現在のペインのIDを取得
-- @return string|nil, string|nil 成功時は (ペインID, nil)、失敗時は (nil, エラーメッセージ)
function M.get_current_pane()
  return exec_tmux("tmux display-message -p '#{pane_id}'")
end

-- コピーモード（スクロールモード）を終了
-- @param pane_id string ペインID
-- @return boolean, string|nil 成功時は (true, nil)、失敗時は (false, エラーメッセージ)
function M.exit_copy_mode(pane_id)
  -- -X cancel: コピーモードを終了
  local cmd = string.format("tmux send-keys -t %s -X cancel", pane_id)
  local _, err = exec_tmux(cmd)
  if err then
    -- コピーモード中でない場合もエラーになるが、それは問題ないので成功として扱う
    return true, nil
  end
  return true, nil
end

-- ペインで動いているプロセスに割り込み信号（Ctrl+C）を送信
-- @param pane_id string ペインID
-- @return boolean, string|nil 成功時は (true, nil)、失敗時は (false, エラーメッセージ)
function M.send_interrupt(pane_id)
  -- C-c: 割り込み信号（SIGINT）を送信
  return M.send_keys(pane_id, "C-c")
end

-- ペインを強制終了
-- @param pane_id string ペインID
-- @return boolean, string|nil 成功時は (true, nil)、失敗時は (false, エラーメッセージ)
function M.kill_pane(pane_id)
  local cmd = string.format("tmux kill-pane -t %s", pane_id)
  local _, err = exec_tmux(cmd)
  if err then
    return false, err
  end
  return true, nil
end

return M
