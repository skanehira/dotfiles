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
-- @param context string|nil ビジュアル選択コンテキスト（送信時にプロンプト先頭に付与）
local function open_input_buffer(tool_name, args, context)
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

  -- 最新のペインIDを取得する関数（存在しない場合は状態をクリアしてnilを返す）
  local function get_current_pane_id()
    local current_id
    if tool_name == "claude" then
      current_id = validate_pane(state.claude_pane)
      if not current_id then
        state.claude_pane = nil
      end
    elseif tool_name == "codex" then
      current_id = validate_pane(state.codex_pane)
      if not current_id then
        state.codex_pane = nil
      end
    end
    return current_id
  end

  -- tmuxペイン作成後、Neovimのリサイズが反映されてからfloatを作成
  local buffer_name = string.format("[%s Input]", tool_name:gsub("^%l", string.upper))
  vim.schedule(function()
    local bufnr = buffer.create_input_buffer({
      name = buffer_name,
      filetype = "markdown",
      on_submit = function(content, submit_bufnr)
        -- 最新のペインIDを取得
        local current_pane = get_current_pane_id()
        if not current_pane then
          vim.notify(string.format("%sペインが見つかりません", tool_name), vim.log.levels.INFO)
          return
        end

        -- ビジュアル選択コンテキストがあればプロンプトの先頭に付与
        local text = content
        local ctx = vim.b[submit_bufnr] and vim.b[submit_bufnr].ai_visual_context or nil
        if ctx then
          text = ctx .. text
        end

        -- Codexの場合はテキストの末尾に改行を追加（Codexは改行がないと送信されない）
        if tool_name == "codex" then
          text = text .. "\n"
        end

        -- テキストをペインに送信
        local success, err = tmux.send_text(current_pane, text)
        if not success then
          vim.notify(string.format("%sへの送信に失敗しました:\n%s", tool_name, err or "不明なエラー"), vim.log.levels.ERROR)
        end
      end,
      on_scroll_down = function()
        local current_pane = get_current_pane_id()
        if not current_pane then
          vim.notify(string.format("%sペインが見つかりません", tool_name), vim.log.levels.INFO)
          return
        end

        local success, err = tmux.send_keys(current_pane, "PageDown")
        if not success then
          vim.notify("PageDownの送信に失敗しました:\n" .. (err or "不明なエラー"), vim.log.levels.WARN)
        end
      end,
      on_scroll_up = function()
        local current_pane = get_current_pane_id()
        if not current_pane then
          vim.notify(string.format("%sペインが見つかりません", tool_name), vim.log.levels.INFO)
          return
        end

        local success, err = tmux.send_keys(current_pane, "PageUp")
        if not success then
          vim.notify("PageUpの送信に失敗しました:\n" .. (err or "不明なエラー"), vim.log.levels.WARN)
        end
      end,
      on_scroll_to_bottom = function()
        local current_pane = get_current_pane_id()
        if not current_pane then
          vim.notify(string.format("%sペインが見つかりません", tool_name), vim.log.levels.INFO)
          return
        end

        local success, err = tmux.send_keys(current_pane, "C-End")
        if not success then
          vim.notify("Ctrl+Endの送信に失敗しました:\n" .. (err or "不明なエラー"), vim.log.levels.WARN)
        end
      end,
      on_interrupt = function()
        local current_pane = get_current_pane_id()
        if not current_pane then
          vim.notify(string.format("%sペインが見つかりません", tool_name), vim.log.levels.INFO)
          return
        end

        local success, err = tmux.kill_pane(current_pane)
        if success then
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
      on_send_tab = function()
        local current_pane = get_current_pane_id()
        if not current_pane then
          vim.notify(string.format("%sペインが見つかりません", tool_name), vim.log.levels.INFO)
          return
        end

        local success, err = tmux.send_keys(current_pane, "Tab")
        if not success then
          vim.notify("Tabの送信に失敗しました:\n" .. (err or "不明なエラー"), vim.log.levels.WARN)
        end
      end,
      on_send_shift_tab = function()
        local current_pane = get_current_pane_id()
        if not current_pane then
          vim.notify(string.format("%sペインが見つかりません", tool_name), vim.log.levels.INFO)
          return
        end

        local success, err = tmux.send_keys(current_pane, "BTab")
        if not success then
          vim.notify("Shift+Tabの送信に失敗しました:\n" .. (err or "不明なエラー"), vim.log.levels.WARN)
        end
      end,
      on_send_space = function()
        local current_pane = get_current_pane_id()
        if not current_pane then
          vim.notify(string.format("%sペインが見つかりません", tool_name), vim.log.levels.INFO)
          return
        end

        local success, err = tmux.send_keys(current_pane, "Space")
        if not success then
          vim.notify("Spaceの送信に失敗しました:\n" .. (err or "不明なエラー"), vim.log.levels.WARN)
        end
      end,
      on_send_ctrl_c = function()
        local current_pane = get_current_pane_id()
        if not current_pane then
          vim.notify(string.format("%sペインが見つかりません", tool_name), vim.log.levels.INFO)
          return
        end

        local success, err = tmux.send_keys(current_pane, "C-c")
        if not success then
          vim.notify("C-cの送信に失敗しました:\n" .. (err or "不明なエラー"), vim.log.levels.WARN)
        end
      end,
      on_send_escape = function()
        local current_pane = get_current_pane_id()
        if not current_pane then
          vim.notify(string.format("%sペインが見つかりません", tool_name), vim.log.levels.INFO)
          return
        end

        local success, err = tmux.send_keys(current_pane, "Escape")
        if not success then
          vim.notify("Escapeの送信に失敗しました:\n" .. (err or "不明なエラー"), vim.log.levels.WARN)
        end
      end,
      on_send_ctrl_v = function()
        local current_pane = get_current_pane_id()
        if not current_pane then
          vim.notify(string.format("%sペインが見つかりません", tool_name), vim.log.levels.INFO)
          return
        end

        local success, err = tmux.send_keys(current_pane, "C-v")
        if not success then
          vim.notify("Ctrl+Vの送信に失敗しました:\n" .. (err or "不明なエラー"), vim.log.levels.WARN)
        end
      end,
      on_send_up = function()
        local current_pane = get_current_pane_id()
        if not current_pane then
          vim.notify(string.format("%sペインが見つかりません", tool_name), vim.log.levels.INFO)
          return
        end

        local success, err = tmux.send_keys(current_pane, "Up")
        if not success then
          vim.notify("Upの送信に失敗しました:\n" .. (err or "不明なエラー"), vim.log.levels.WARN)
        end
      end,
      on_send_down = function()
        local current_pane = get_current_pane_id()
        if not current_pane then
          vim.notify(string.format("%sペインが見つかりません", tool_name), vim.log.levels.INFO)
          return
        end

        local success, err = tmux.send_keys(current_pane, "Down")
        if not success then
          vim.notify("Downの送信に失敗しました:\n" .. (err or "不明なエラー"), vim.log.levels.WARN)
        end
      end,
      on_send_left = function()
        local current_pane = get_current_pane_id()
        if not current_pane then
          vim.notify(string.format("%sペインが見つかりません", tool_name), vim.log.levels.INFO)
          return
        end

        local success, err = tmux.send_keys(current_pane, "Left")
        if not success then
          vim.notify("Leftの送信に失敗しました:\n" .. (err or "不明なエラー"), vim.log.levels.WARN)
        end
      end,
      on_send_right = function()
        local current_pane = get_current_pane_id()
        if not current_pane then
          vim.notify(string.format("%sペインが見つかりません", tool_name), vim.log.levels.INFO)
          return
        end

        local success, err = tmux.send_keys(current_pane, "Right")
        if not success then
          vim.notify("Rightの送信に失敗しました:\n" .. (err or "不明なエラー"), vim.log.levels.WARN)
        end
      end,
    })
    -- ビジュアル選択コンテキストをバッファ変数に保存（送信時に参照）
    if context and context ~= "" then
      vim.b[bufnr].ai_visual_context = context
    else
      vim.b[bufnr].ai_visual_context = nil
    end
  end)
end

-- Claudeを開く
-- @param args string|nil コマンド引数
-- @param context string|nil ビジュアル選択コンテキスト
function M.open_claude(args, context)
  local base_args = ''
  if args and args ~= "" then
    args = base_args .. " " .. args
  else
    args = base_args
  end
  open_input_buffer("claude", args, context)
end

-- Codexを開く
-- @param args string|nil コマンド引数
-- @param context string|nil ビジュアル選択コンテキスト
function M.open_codex(args, context)
  open_input_buffer("codex", args, context)
end

-- ビジュアル選択からファイルコンテキストを取得
-- @return string "@/path/to/file#Lstart-end " 形式のコンテキスト
local function get_visual_context()
  local file_path = vim.fn.expand("%:p")
  local start_line = vim.fn.line("v")
  local end_line = vim.fn.line(".")
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end
  return string.format("@%s#L%d-%d ", file_path, start_line, end_line)
end

-- ビジュアルモード用キーマップのヘルパー
-- @param open_fn function(context) ツールを開く関数
local function visual_keymap_handler(open_fn)
  return function()
    local ctx = get_visual_context()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
    vim.schedule(function()
      open_fn(ctx)
    end)
  end
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

  local map_opts = { noremap = true, silent = true }

  -- キーマップ: Claude（ノーマルモード）
  vim.keymap.set("n", "<leader>ac", "<Cmd>Claude<CR>",
    vim.tbl_extend("force", map_opts, { desc = "Open Claude" }))

  vim.keymap.set("n", "<leader>ar", "<Cmd>Claude -r<CR>",
    vim.tbl_extend("force", map_opts, { desc = "Open Claude with -r" }))

  vim.keymap.set("n", "<leader>aC", "<Cmd>Claude -c<CR>",
    vim.tbl_extend("force", map_opts, { desc = "Open Claude with -c" }))

  -- キーマップ: Claude（ビジュアルモード）
  vim.keymap.set("x", "<leader>ac", visual_keymap_handler(function(ctx)
    M.open_claude("", ctx)
  end), vim.tbl_extend("force", map_opts, { desc = "Open Claude with selection context" }))

  vim.keymap.set("x", "<leader>ar", visual_keymap_handler(function(ctx)
    M.open_claude("-r", ctx)
  end), vim.tbl_extend("force", map_opts, { desc = "Open Claude -r with selection context" }))

  vim.keymap.set("x", "<leader>aC", visual_keymap_handler(function(ctx)
    M.open_claude("-c", ctx)
  end), vim.tbl_extend("force", map_opts, { desc = "Open Claude -c with selection context" }))

  -- キーマップ: Codex（ノーマルモード）
  vim.keymap.set("n", "<leader>xx", "<Cmd>Codex<CR>",
    vim.tbl_extend("force", map_opts, { desc = "Open Codex" }))

  vim.keymap.set("n", "<leader>xr", "<Cmd>Codex resume<CR>",
    vim.tbl_extend("force", map_opts, { desc = "Open Codex resume" }))

  vim.keymap.set("n", "<leader>xc", "<Cmd>Codex resume --last<CR>",
    vim.tbl_extend("force", map_opts, { desc = "Open Codex resume --last" }))

  -- キーマップ: Codex（ビジュアルモード）
  vim.keymap.set("x", "<leader>xx", visual_keymap_handler(function(ctx)
    M.open_codex("", ctx)
  end), vim.tbl_extend("force", map_opts, { desc = "Open Codex with selection context" }))

  vim.keymap.set("x", "<leader>xr", visual_keymap_handler(function(ctx)
    M.open_codex("resume", ctx)
  end), vim.tbl_extend("force", map_opts, { desc = "Open Codex resume with selection context" }))

  vim.keymap.set("x", "<leader>xc", visual_keymap_handler(function(ctx)
    M.open_codex("resume --last", ctx)
  end), vim.tbl_extend("force", map_opts, { desc = "Open Codex resume --last with selection context" }))
end

return M
