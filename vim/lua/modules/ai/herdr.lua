-- herdr操作の低レベルAPI
-- このモジュールは外部状態を持たず、純粋にherdrコマンドのラッパーとして機能する

local M = {}

-- herdr管理下のペイン内で実行されているかチェック
-- @return boolean herdr管理下のペイン内ならtrue
function M.is_in_herdr()
  return vim.env.HERDR_ENV == "1"
end

-- herdrコマンドを実行してエラーハンドリング
-- 引数はリストで渡し、シェルを経由せず直接実行する（クォートエスケープ不要）
-- @param args table コマンドと引数のリスト（例: {"herdr", "pane", "get", "w1:p1"}）
-- @return string|nil, string|nil 成功時は (出力, nil)、失敗時は (nil, エラーメッセージ)
local function exec_herdr(args)
  local result = vim.fn.system(args)
  if vim.v.shell_error ~= 0 then
    local error_msg = string.format(
      "herdr command failed (exit code: %d)\nCommand: %s\nOutput: %s",
      vim.v.shell_error,
      table.concat(args, " "),
      vim.trim(result)
    )
    return nil, error_msg
  end
  return vim.trim(result), nil
end

-- JSON レスポンスから result.pane.pane_id を取り出す
-- @param json_str string herdrコマンドのJSON出力
-- @return string|nil pane_id、取り出せない場合はnil
local function parse_pane_id(json_str)
  local ok, decoded = pcall(vim.json.decode, json_str)
  if not ok or not decoded.result or not decoded.result.pane then
    return nil
  end
  return decoded.result.pane.pane_id
end

-- 現在のペインを右方向に分割して新規ペインを作成し、コマンドを実行する
-- @param size_percent number 新規ペインのサイズ（%）
-- @param shell_command string|nil 実行するコマンド（省略時は通常のシェル）
-- @return string|nil, string|nil 成功時は (ペインID, nil)、失敗時は (nil, エラーメッセージ)
function M.create_pane(size_percent, shell_command)
  local ratio = tostring(size_percent / 100)
  local output, err = exec_herdr({
    "herdr", "pane", "split", "--current", "--direction", "right",
    "--ratio", ratio, "--no-focus",
  })
  if not output then
    return nil, err
  end

  local pane_id = parse_pane_id(output)
  if not pane_id then
    return nil, "Failed to parse pane ID from output: " .. output
  end

  if shell_command then
    local _, run_err = exec_herdr({ "herdr", "pane", "run", pane_id, shell_command })
    if run_err then
      return nil, run_err
    end
  end

  return pane_id, nil
end

-- ペインが存在するかチェック
-- @param pane_id string ペインID（例: "w1:p1"）
-- @return boolean 存在すればtrue
function M.pane_exists(pane_id)
  local _, err = exec_herdr({ "herdr", "pane", "get", pane_id })
  return err == nil
end

-- 現在のタブ内で指定エージェントが動いているペインを検索
-- @param pattern string エージェント名（"claude" または "codex"）
-- @return string|nil ペインID、見つからない場合はnil
function M.find_pane_by_command(pattern)
  local workspace_id = vim.env.HERDR_WORKSPACE_ID
  local tab_id = vim.env.HERDR_TAB_ID
  if not workspace_id or not tab_id then
    return nil
  end

  local output = exec_herdr({ "herdr", "pane", "list", "--workspace", workspace_id })
  if not output then
    return nil
  end

  local ok, decoded = pcall(vim.json.decode, output)
  if not ok or not decoded.result or not decoded.result.panes then
    return nil
  end

  for _, pane in ipairs(decoded.result.panes) do
    if pane.tab_id == tab_id and pane.agent == pattern then
      return pane.pane_id
    end
  end
  return nil
end

-- ペインにキーを送信
-- @param pane_id string ペインID
-- @param keys string|table 送信するキー（例: "ctrl+c"）。複数キーを連続送信する場合は配列（例: {"esc", "esc"}）
-- @return boolean, string|nil 成功時は (true, nil)、失敗時は (false, エラーメッセージ)
function M.send_keys(pane_id, keys)
  local key_list = type(keys) == "table" and keys or { keys }
  local args = { "herdr", "pane", "send-keys", pane_id }
  for _, k in ipairs(key_list) do
    table.insert(args, k)
  end
  local _, err = exec_herdr(args)
  if err then
    return false, err
  end
  return true, nil
end

-- ペインにテキストを送信し、Enterキーで実行する
-- @param pane_id string ペインID
-- @param text string 送信するテキスト
-- @return boolean, string|nil 成功時は (true, nil)、失敗時は (false, エラーメッセージ)
function M.send_text(pane_id, text)
  local _, err = exec_herdr({ "herdr", "pane", "run", pane_id, text })
  if err then
    return false, err
  end
  return true, nil
end

-- 現在のペインのIDを取得
-- @return string|nil, string|nil 成功時は (ペインID, nil)、失敗時は (nil, エラーメッセージ)
function M.get_current_pane()
  local output, err = exec_herdr({ "herdr", "pane", "current", "--current" })
  if not output then
    return nil, err
  end
  local pane_id = parse_pane_id(output)
  if not pane_id then
    return nil, "Failed to parse pane ID from output: " .. output
  end
  return pane_id, nil
end

-- ペインで動いているプロセスに割り込み信号（Ctrl+C）を送信
-- @param pane_id string ペインID
-- @return boolean, string|nil 成功時は (true, nil)、失敗時は (false, エラーメッセージ)
function M.send_interrupt(pane_id)
  return M.send_keys(pane_id, "ctrl+c")
end

-- ペインを強制終了
-- @param pane_id string ペインID
-- @return boolean, string|nil 成功時は (true, nil)、失敗時は (false, エラーメッセージ)
function M.kill_pane(pane_id)
  local _, err = exec_herdr({ "herdr", "pane", "close", pane_id })
  if err then
    return false, err
  end
  return true, nil
end

return M
