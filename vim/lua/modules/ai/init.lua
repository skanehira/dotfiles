-- AIツール（Claude/Codex）のtmux統合モジュール
-- 公開APIとコマンド登録を提供

local tmux = require("modules.ai.tmux")
local buffer = require("modules.ai.buffer")

local M = {}

-- 内部状態: ペインIDを保持
local state = {
  claude_pane = nil,
  codex_pane = nil,
}

-- ペインIDを検証し、存在しない場合はクリア
-- @param pane_id string|nil ペインID
-- @return string|nil 有効なペインID、または nil
local function validate_pane(pane_id)
  if not pane_id then
    return nil
  end

  if tmux.pane_exists(pane_id) then
    return pane_id
  end

  return nil
end

-- ペインを取得または作成
-- @param tool_name string ツール名（"claude" または "codex"）
-- @param args string|nil コマンド引数（例: "-c" や "-r abc123"）
-- @return string|nil ペインID、失敗時は nil
local function get_or_create_pane(tool_name, args)
  -- 状態からペインIDを取得
  local pane_id
  if tool_name == "claude" then
    pane_id = validate_pane(state.claude_pane)
  elseif tool_name == "codex" then
    pane_id = validate_pane(state.codex_pane)
  end

  -- メモリ上にない場合、現在のウィンドウ内でコマンド名で検索して復元
  if not pane_id then
    pane_id = tmux.find_pane_by_command(tool_name)
    if pane_id then
      -- 状態を復元
      if tool_name == "claude" then
        state.claude_pane = pane_id
      elseif tool_name == "codex" then
        state.codex_pane = pane_id
      end
    end
  end

  -- ペインが存在すれば再利用
  if pane_id then
    return pane_id
  end

  -- コマンドを構築（引数があれば追加）
  local command = tool_name
  if args and args ~= "" then
    command = string.format("%s %s", tool_name, args)
  end

  -- 新規ペインを作成（30%）、ツールを起動
  -- コマンド終了時にペインも自動的に閉じられる
  local err
  pane_id, err = tmux.create_pane(40, command)
  if not pane_id then
    vim.notify("tmuxペインの作成に失敗しました:\n" .. (err or "不明なエラー"), vim.log.levels.ERROR)
    return nil
  end

  -- 状態を更新
  if tool_name == "claude" then
    state.claude_pane = pane_id
  elseif tool_name == "codex" then
    state.codex_pane = pane_id
  end

  return pane_id
end

-- 入力バッファを開く共通処理
-- @param tool_name string ツール名（"claude" または "codex"）
-- @param args string|nil コマンド引数
local function open_input_buffer(tool_name, args)
  -- tmuxセッション内かチェック
  if not tmux.is_in_tmux() then
    vim.notify("エラー: このコマンドはtmuxセッション内でのみ使用できます", vim.log.levels.ERROR)
    return
  end

  -- ペインを取得または作成
  local pane_id = get_or_create_pane(tool_name, args)
  if not pane_id then
    return
  end

  -- 最新のペインIDを取得する関数
  local function get_current_pane_id()
    if tool_name == "claude" then
      return state.claude_pane
    elseif tool_name == "codex" then
      return state.codex_pane
    end
    return nil
  end

  -- 入力バッファを作成
  local buffer_name = string.format("[%s Input]", tool_name:gsub("^%l", string.upper))
  buffer.create_input_buffer({
    name = buffer_name,
    filetype = "markdown",
    on_submit = function(content, bufnr)
      -- 最新のペインIDを取得
      local current_pane = get_current_pane_id()
      if not current_pane then
        vim.notify(string.format("%sペインが見つかりません", tool_name), vim.log.levels.ERROR)
        return
      end

      -- スクロール中の場合はコピーモードを終了
      tmux.exit_copy_mode(current_pane)

      -- Codexの場合はテキストの末尾に改行を追加（Codexは改行がないと送信されない）
      local text = content
      if tool_name == "codex" then
        text = content .. "\n"
      end

      -- テキストをペインに送信
      local success, err = tmux.send_text(current_pane, text)
      if not success then
        vim.notify(string.format("%sへの送信に失敗しました:\n%s", tool_name, err or "不明なエラー"), vim.log.levels.ERROR)
      end

      -- バッファを閉じる
      buffer.close_buffer(bufnr)
    end,
    on_scroll_down = function()
      -- 最新のペインIDを取得
      local current_pane = get_current_pane_id()
      if not current_pane then
        vim.notify(string.format("%sペインが見つかりません", tool_name), vim.log.levels.ERROR)
        return
      end

      local success, err = tmux.scroll(current_pane, "down")
      if not success then
        vim.notify("ペインのスクロールダウンに失敗しました:\n" .. (err or "不明なエラー"), vim.log.levels.WARN)
      end
    end,
    on_scroll_up = function()
      -- 最新のペインIDを取得
      local current_pane = get_current_pane_id()
      if not current_pane then
        vim.notify(string.format("%sペインが見つかりません", tool_name), vim.log.levels.ERROR)
        return
      end

      local success, err = tmux.scroll(current_pane, "up")
      if not success then
        vim.notify("ペインのスクロールアップに失敗しました:\n" .. (err or "不明なエラー"), vim.log.levels.WARN)
      end
    end,
    on_interrupt = function()
      -- 最新のペインIDを取得
      local current_pane = get_current_pane_id()
      if not current_pane then
        vim.notify(string.format("%sペインが見つかりません", tool_name), vim.log.levels.ERROR)
        return
      end

      local success, err = tmux.kill_pane(current_pane)
      if success then
        -- ペインを削除したので状態もクリア
        if tool_name == "claude" then
          state.claude_pane = nil
        elseif tool_name == "codex" then
          state.codex_pane = nil
        end
        vim.notify(string.format("%sペインを終了しました", tool_name), vim.log.levels.INFO)
      else
        vim.notify(string.format("%sペインの終了に失敗しました:\n%s", tool_name, err or "不明なエラー"), vim.log.levels.ERROR)
      end
    end,
    on_scroll_line_down = function()
      -- 最新のペインIDを取得
      local current_pane = get_current_pane_id()
      if not current_pane then
        vim.notify(string.format("%sペインが見つかりません", tool_name), vim.log.levels.ERROR)
        return
      end

      -- コピーモードなら1行スクロール、そうでなければC-nを送信
      if tmux.is_in_copy_mode(current_pane) then
        local success, err = tmux.scroll_line(current_pane, "down")
        if not success then
          vim.notify("ペインの1行スクロールダウンに失敗しました:\n" .. (err or "不明なエラー"), vim.log.levels.WARN)
        end
      else
        local success, err = tmux.send_keys(current_pane, "C-n")
        if not success then
          vim.notify("C-nの送信に失敗しました:\n" .. (err or "不明なエラー"), vim.log.levels.WARN)
        end
      end
    end,
    on_scroll_line_up = function()
      -- 最新のペインIDを取得
      local current_pane = get_current_pane_id()
      if not current_pane then
        vim.notify(string.format("%sペインが見つかりません", tool_name), vim.log.levels.ERROR)
        return
      end

      -- コピーモードなら1行スクロール、そうでなければC-pを送信
      if tmux.is_in_copy_mode(current_pane) then
        local success, err = tmux.scroll_line(current_pane, "up")
        if not success then
          vim.notify("ペインの1行スクロールアップに失敗しました:\n" .. (err or "不明なエラー"), vim.log.levels.WARN)
        end
      else
        local success, err = tmux.send_keys(current_pane, "C-p")
        if not success then
          vim.notify("C-pの送信に失敗しました:\n" .. (err or "不明なエラー"), vim.log.levels.WARN)
        end
      end
    end,
    on_send_tab = function()
      -- 最新のペインIDを取得
      local current_pane = get_current_pane_id()
      if not current_pane then
        vim.notify(string.format("%sペインが見つかりません", tool_name), vim.log.levels.ERROR)
        return
      end

      local success, err = tmux.send_keys(current_pane, "Tab")
      if not success then
        vim.notify("Tabの送信に失敗しました:\n" .. (err or "不明なエラー"), vim.log.levels.WARN)
      end
    end,
    on_send_shift_tab = function()
      -- 最新のペインIDを取得
      local current_pane = get_current_pane_id()
      if not current_pane then
        vim.notify(string.format("%sペインが見つかりません", tool_name), vim.log.levels.ERROR)
        return
      end

      local success, err = tmux.send_keys(current_pane, "BTab")
      if not success then
        vim.notify("Shift+Tabの送信に失敗しました:\n" .. (err or "不明なエラー"), vim.log.levels.WARN)
      end
    end,
    on_exit_copy_mode = function()
      -- 最新のペインIDを取得
      local current_pane = get_current_pane_id()
      if not current_pane then
        vim.notify(string.format("%sペインが見つかりません", tool_name), vim.log.levels.ERROR)
        return
      end

      tmux.exit_copy_mode(current_pane)
    end,
  })
end

-- Claudeを開く
-- @param args string|nil コマンド引数
function M.open_claude(args)
  open_input_buffer("claude", args)
end

-- Codexを開く
-- @param args string|nil コマンド引数
function M.open_codex(args)
  open_input_buffer("codex", args)
end

-- モジュールを初期化してコマンドとキーマップを登録
function M.setup()
  -- :Claude コマンド（引数を受け取る）
  vim.api.nvim_create_user_command("Claude", function(opts)
    M.open_claude(opts.args)
  end, {
    nargs = "*",
    desc = "Open Claude in tmux pane with input buffer",
  })

  -- :Codex コマンド（引数を受け取る）
  vim.api.nvim_create_user_command("Codex", function(opts)
    M.open_codex(opts.args)
  end, {
    nargs = "*",
    desc = "Open Codex in tmux pane with input buffer",
  })

  -- キーマップ: Claude
  vim.keymap.set("n", "<leader>ac", "<Cmd>Claude<CR>", {
    noremap = true,
    silent = true,
    desc = "Open Claude",
  })

  vim.keymap.set("n", "<leader>ar", "<Cmd>Claude -r<CR>", {
    noremap = true,
    silent = true,
    desc = "Open Claude with -r",
  })

  vim.keymap.set("n", "<leader>aC", "<Cmd>Claude -c<CR>", {
    noremap = true,
    silent = true,
    desc = "Open Claude with -c",
  })

  -- キーマップ: Codex
  vim.keymap.set("n", "<leader>xx", "<Cmd>Codex<CR>", {
    noremap = true,
    silent = true,
    desc = "Open Codex",
  })

  vim.keymap.set("n", "<leader>xr", "<Cmd>Codex resume<CR>", {
    noremap = true,
    silent = true,
    desc = "Open Codex resume",
  })

  vim.keymap.set("n", "<leader>xc", "<Cmd>Codex resume --last<CR>", {
    noremap = true,
    silent = true,
    desc = "Open Codex resume --last",
  })
end

return M
