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

-- JSON レスポンスから result.pane.pane_id を取り出す（pane split / pane current 用）
-- @param json_str string herdrコマンドのJSON出力
-- @return string|nil pane_id、取り出せない場合はnil
local function parse_pane_id(json_str)
  local ok, decoded = pcall(vim.json.decode, json_str)
  if not ok or not decoded.result or not decoded.result.pane then
    return nil
  end
  return decoded.result.pane.pane_id
end

local function rename_agent_when_detected(pane_id, name)
  local attempts = 0
  local function rename()
    attempts = attempts + 1
    local _, err = exec_herdr({ "herdr", "agent", "rename", pane_id, name })
    if err then
      if attempts < 60 then
        vim.defer_fn(rename, 1000)
      else
        vim.notify("herdrエージェント名の設定に失敗しました:\n" .. err, vim.log.levels.WARN)
      end
    end
  end
  vim.defer_fn(rename, 100)
end

-- 現在のペインを右方向に分割し、新しいペインでエージェントを起動する
-- @param size_percent number 新規ペインのサイズ（%）
-- @param argv table 実行するコマンドと引数のリスト（例: {"claude", "-r"}）
-- @param name string|nil エージェント名（省略時は argv[1]）
-- @return string|nil, string|nil 成功時は (ペインID, nil)、失敗時は (nil, エラーメッセージ)
function M.create_pane(size_percent, argv, name)
  local tab_id = vim.env.HERDR_TAB_ID
  if not tab_id then
    return nil, "HERDR_TAB_ID is not set (not running inside a herdr pane)"
  end

  -- agent name はグローバル一意が必要なため、エージェント名 + タブIDで構成する
  local agent_name = string.format("%s-%s", name or argv[1], tab_id:gsub(":", "-"):lower())

  local split_output, split_err = exec_herdr({
    "herdr", "pane", "split", "--current",
    "--direction", "right",
    "--cwd", vim.fn.getcwd(),
    "--no-focus",
  })
  if not split_output then
    return nil, split_err
  end

  local pane_id = parse_pane_id(split_output)
  if not pane_id then
    return nil, "Failed to parse pane ID from output: " .. split_output
  end

  local escaped_argv = {}
  for _, arg in ipairs(argv) do
    table.insert(escaped_argv, vim.fn.shellescape(arg))
  end
  local _, run_err = exec_herdr({
    "herdr", "pane", "run", pane_id,
    "exec " .. table.concat(escaped_argv, " "),
  })
  if run_err then
    exec_herdr({ "herdr", "pane", "close", pane_id })
    return nil, run_err
  end
  rename_agent_when_detected(pane_id, agent_name)

  -- pane split の既定比率 50/50 を、既存挙動の 40/60 に合わせてリサイズする
  local target_ratio = size_percent / 100
  local _, resize_err = exec_herdr({
    "herdr", "pane", "resize", "--pane", pane_id,
    "--direction", "left", "--amount", tostring(0.5 - target_ratio),
  })
  if resize_err then
    return nil, resize_err
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

-- 現在のタブ内で指定エージェントが動いているペインを alias で検索
-- @param pattern string エージェント名（"claude" / "claude-spark" / "codex" / "opencode"）
-- @return string|nil ペインID、見つからない場合はnil
function M.find_pane_by_command(pattern)
  local tab_id = vim.env.HERDR_TAB_ID
  if not tab_id then
    return nil
  end

  local output = exec_herdr({ "herdr", "agent", "list" })
  if not output then
    return nil
  end

  local ok, decoded = pcall(vim.json.decode, output)
  if not ok or not decoded.result or not decoded.result.agents then
    return nil
  end

  local expected_name = string.format("%s-%s", pattern, tab_id:gsub(":", "-"):lower())
  for _, agent in ipairs(decoded.result.agents) do
    if agent.tab_id == tab_id and agent.name == expected_name then
      return agent.pane_id
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
