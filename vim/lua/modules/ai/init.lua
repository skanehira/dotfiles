-- AIツール（Claude/Codex）のherdr統合モジュール
-- 公開APIとコマンド登録を提供

local herdr = require("modules.ai.herdr")
local buffer = require("modules.ai.buffer")
local comments = require("modules.ai.comments")

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

  if herdr.pane_exists(pane_id) then
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
    pane_id = herdr.find_pane_by_command(tool_name)
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
  pane_id, err = herdr.create_pane(40, command)
  if not pane_id then
    vim.notify("herdrペインの作成に失敗しました:\n" .. (err or "不明なエラー"), vim.log.levels.ERROR)
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

-- ツール名に応じて末尾改行を付与（Codex は改行が無いと送信されない）
local function finalize_text(tool_name, text)
  if tool_name == "codex" then
    return text .. "\n"
  end
  return text
end

-- 2つの context が同一かを判定（書きかけ内容の保持判定に使う）
local function same_context(a, b)
  if a == nil and b == nil then
    return true
  end
  if a == nil or b == nil then
    return false
  end
  return a.file_path == b.file_path
      and a.start_line == b.start_line
      and a.end_line == b.end_line
end

-- 入力バッファを開く共通処理
-- @param tool_name string ツール名（"claude" または "codex"）
-- @param args string|nil コマンド引数
-- @param context table|nil コメントコンテキスト
--   { file_path = string, scope = "range"|"file", start_line = number?, end_line = number? }
local function open_input_buffer(tool_name, args, context)
  -- herdrペイン内かチェック
  if not herdr.is_in_herdr() then
    vim.notify("エラー: このコマンドはherdrペイン内でのみ使用できます", vim.log.levels.ERROR)
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

  -- herdrペイン作成後、Neovimのリサイズが反映されてからfloatを作成
  local buffer_name = string.format("[%s Input]", tool_name:gsub("^%l", string.upper))
  vim.schedule(function()
    local buf_config = {
      name = buffer_name,
      filetype = "markdown",
      on_submit = function(content, submit_bufnr)
        local ctx = vim.b[submit_bufnr] and vim.b[submit_bufnr].ai_context or nil
        local message = vim.trim(content)

        -- コンテキストが無い（ノーマルモード起動 = 即送信モード）
        if not ctx then
          local current_pane = get_current_pane_id()
          if not current_pane then
            vim.notify(string.format("%sペインが見つかりません", tool_name), vim.log.levels.INFO)
            return
          end
          local ok, err = herdr.send_text(current_pane, finalize_text(tool_name, message))
          if not ok then
            vim.notify(string.format("%sへの送信に失敗しました:\n%s", tool_name, err or "不明なエラー"),
              vim.log.levels.ERROR)
          end
          return
        end

        -- コンテキストあり（範囲選択） → コメントスタック操作
        local existing = comments.get(tool_name, ctx.file_path, ctx.start_line, ctx.end_line)

        local function close_float()
          local win = vim.api.nvim_get_current_win()
          if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
          end
        end

        -- 内容空 + 既存あり → 削除
        if message == "" then
          if existing then
            comments.delete(tool_name, ctx.file_path, ctx.start_line, ctx.end_line)
            vim.notify(
              string.format("[%s] コメントを削除しました（残 %d 件）", tool_name, comments.count(tool_name)),
              vim.log.levels.INFO
            )
            close_float()
          else
            vim.notify("コメントが空です", vim.log.levels.WARN)
          end
          return
        end

        -- 通常: 保存（新規 or 上書き）
        local _, was_new = comments.set(tool_name, ctx.file_path, ctx.start_line, ctx.end_line, message)
        local action = was_new and "保存" or "更新"
        vim.notify(
          string.format("[%s] コメントを%sしました（合計 %d 件）", tool_name, action, comments.count(tool_name)),
          vim.log.levels.INFO
        )
        close_float()
      end,
      on_submit_immediate = function(content, submit_bufnr)
        local message = vim.trim(content)
        if message == "" then
          return
        end
        local current_pane = get_current_pane_id()
        if not current_pane then
          vim.notify(string.format("%sペインが見つかりません", tool_name), vim.log.levels.INFO)
          return
        end
        local ctx = vim.b[submit_bufnr] and vim.b[submit_bufnr].ai_context or nil
        local text = message
        if ctx then
          text = string.format("@%s#L%d-%d %s", ctx.file_path, ctx.start_line, ctx.end_line, message)
        end
        local ok, err = herdr.send_text(current_pane, finalize_text(tool_name, text))
        if not ok then
          vim.notify(string.format("%sへの送信に失敗しました:\n%s", tool_name, err or "不明なエラー"),
            vim.log.levels.ERROR)
        end
      end,
      on_interrupt = function()
        local current_pane = get_current_pane_id()
        if not current_pane then
          vim.notify(string.format("%sペインが見つかりません", tool_name), vim.log.levels.INFO)
          return
        end

        local success, err = herdr.kill_pane(current_pane)
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
    }
    -- herdrペインへ単純にキーを送る callback を一括生成
    -- { cb = bufferモジュール側のコールバック名, key = herdr send-keys に渡すキー名（配列なら複数キーを連続送信）, label = エラー表示用ラベル }
    local passthrough_keys = {
      { cb = "on_send_tab",           key = "tab",              label = "Tab" },
      { cb = "on_send_shift_tab",     key = "shift+tab",        label = "Shift+Tab" },
      { cb = "on_send_space",         key = "space",            label = "Space" },
      { cb = "on_send_ctrl_c",        key = "ctrl+c",           label = "C-c" },
      { cb = "on_send_escape",        key = "esc",              label = "Escape" },
      -- 1コマンドで2連送信することで、Claudeのrewind検出タイムウィンドウ内に確実に届ける
      { cb = "on_send_double_escape", key = { "esc", "esc" },   label = "Escape x2" },
      { cb = "on_send_ctrl_v",        key = "ctrl+v",           label = "Ctrl+V" },
      { cb = "on_send_up",            key = "up",               label = "Up" },
      { cb = "on_send_down",          key = "down",             label = "Down" },
      { cb = "on_send_left",          key = "left",             label = "Left" },
      { cb = "on_send_right",         key = "right",            label = "Right" },
    }
    -- ループ変数の closure キャプチャを避けるため factory で生成
    local function make_send_keys_callback(key_name, label)
      return function()
        local current_pane = get_current_pane_id()
        if not current_pane then
          vim.notify(string.format("%sペインが見つかりません", tool_name), vim.log.levels.INFO)
          return
        end
        local success, err = herdr.send_keys(current_pane, key_name)
        if not success then
          vim.notify(string.format("%sの送信に失敗しました:\n%s", label, err or "不明なエラー"), vim.log.levels.WARN)
        end
      end
    end
    for _, p in ipairs(passthrough_keys) do
      buf_config[p.cb] = make_send_keys_callback(p.key, p.label)
    end
    local bufnr = buffer.create_input_buffer(buf_config)
    -- バッファ内容の判定（書きかけがあるか）
    local current_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local is_buffer_empty = (#current_lines == 0)
        or (#current_lines == 1 and current_lines[1] == "")

    local prev_context = vim.b[bufnr].ai_context

    -- 同じ context かつ書きかけが残っている場合のみ保持（q で閉じた直後の再オープン）
    -- それ以外（context が変わった or バッファが空）は preload/clear で入れ替える
    if same_context(prev_context, context) and not is_buffer_empty then
      -- 何もしない（書きかけを保持）
    elseif context then
      vim.b[bufnr].ai_context = context
      local existing = comments.get(tool_name, context.file_path, context.start_line, context.end_line)
      if existing then
        local preload = vim.split(existing, "\n", { plain = true })
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, preload)
        local last_row = #preload
        local last_col = #preload[last_row]
        pcall(vim.api.nvim_win_set_cursor, 0, { last_row, last_col })
      else
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
      end
    else
      vim.b[bufnr].ai_context = nil
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
    end
  end)
end

-- ビジュアル選択から範囲コンテキストを構築
local function get_visual_context()
  local file_path = vim.fn.expand("%:p")
  if file_path == "" then
    return nil
  end
  -- :p で正規化（comments モジュール側のキーと揃える）
  file_path = vim.fn.fnamemodify(file_path, ":p")
  local start_line = vim.fn.line("v")
  local end_line = vim.fn.line(".")
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end
  return {
    file_path = file_path,
    start_line = start_line,
    end_line = end_line,
  }
end

-- カーソル行を含むスタック済みコメントがあれば、その範囲を context として返す
local function find_thread_context_at_cursor(tool_name)
  local file_path = vim.fn.expand("%:p")
  if file_path == "" then
    return nil
  end
  file_path = vim.fn.fnamemodify(file_path, ":p")
  local line = vim.fn.line(".")
  local t = comments.find_at_line(tool_name, file_path, line)
  if not t then
    return nil
  end
  return {
    file_path = file_path,
    start_line = t.start_line,
    end_line = t.end_line,
  }
end

-- Claudeを開く
-- @param args string|nil コマンド引数
-- @param context table|nil 範囲コンテキスト
-- context が無い場合の挙動:
--   - カーソル行にスタック済みコメントがあれば、それを編集モードで開く
--   - 無ければ即送信モード
function M.open_claude(args, context)
  local base_args = ''
  if args and args ~= "" then
    args = base_args .. " " .. args
  else
    args = base_args
  end
  open_input_buffer("claude", args, context or find_thread_context_at_cursor("claude"))
end

-- Codexを開く（context 無し時は Claude 同様にカーソル位置のスレッドを検索）
-- @param args string|nil コマンド引数
-- @param context table|nil 範囲コンテキスト
function M.open_codex(args, context)
  open_input_buffer("codex", args, context or find_thread_context_at_cursor("codex"))
end

-- コメントスタックを一括送信
function M.submit(tool_name)
  if not herdr.is_in_herdr() then
    vim.notify("エラー: このコマンドはherdrペイン内でのみ使用できます", vim.log.levels.ERROR)
    return
  end

  local text = comments.format_for_submit(tool_name)
  if not text then
    vim.notify(string.format("[%s] コメントスタックは空です", tool_name), vim.log.levels.INFO)
    return
  end

  local pane_id = get_or_create_pane(tool_name, "")
  if not pane_id then
    return
  end

  local ok, err = herdr.send_text(pane_id, finalize_text(tool_name, text))
  if not ok then
    vim.notify(string.format("%sへの送信に失敗しました:\n%s", tool_name, err or "不明なエラー"),
      vim.log.levels.ERROR)
    return
  end

  local cleared = comments.count(tool_name)
  comments.clear(tool_name)
  vim.notify(string.format("[%s] %d 件のコメントを送信しました", tool_name, cleared), vim.log.levels.INFO)
end

-- コメントスタックを破棄
function M.clear_comments(tool_name)
  local n = comments.count(tool_name)
  comments.clear(tool_name)
  vim.notify(string.format("[%s] %d 件のコメントをクリアしました", tool_name, n), vim.log.levels.INFO)
end

-- カーソル行を含むコメントを削除
function M.delete_comment_at_cursor(tool_name)
  local file_path = vim.fn.expand("%:p")
  if file_path == "" then
    vim.notify("ファイルバッファではありません", vim.log.levels.WARN)
    return
  end
  file_path = vim.fn.fnamemodify(file_path, ":p")
  local line = vim.fn.line(".")
  local removed = comments.delete_at_line(tool_name, file_path, line)
  if removed == 0 then
    vim.notify(string.format("[%s] カーソル行 (%d) にコメントはありません", tool_name, line), vim.log.levels.INFO)
  else
    vim.notify(
      string.format("[%s] %d 件のコメントを削除しました（残 %d 件）", tool_name, removed, comments.count(tool_name)),
      vim.log.levels.INFO
    )
  end
end

-- コメントスタックを quickfix に表示
function M.list_comments(tool_name)
  local threads = comments.list(tool_name)
  if #threads == 0 then
    vim.notify(string.format("[%s] コメントスタックは空です", tool_name), vim.log.levels.INFO)
    return
  end

  local items = {}
  for _, t in ipairs(threads) do
    -- 改行をスペースに圧縮してプレビュー
    local preview = (t.message or ""):gsub("\n", " / ")
    table.insert(items, {
      filename = t.file_path,
      lnum = t.start_line,
      end_lnum = t.end_line,
      text = string.format("[#%d] %s", t.id, preview),
    })
  end

  vim.fn.setqflist({}, " ", { title = string.format("%s comments", tool_name), items = items })
  vim.cmd("copen")
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
  -- コメントスタックの初期化（namespace, autocmd, ハイライト）
  comments.setup()

  -- :Claude コマンド（引数を受け取る）
  vim.api.nvim_create_user_command("Claude", function(opts)
    M.open_claude(opts.args)
  end, {
    nargs = "*",
    desc = "Open Claude in herdr pane with input buffer",
  })

  -- :Codex コマンド（引数を受け取る）
  vim.api.nvim_create_user_command("Codex", function(opts)
    M.open_codex(opts.args)
  end, {
    nargs = "*",
    desc = "Open Codex in herdr pane with input buffer",
  })

  -- コメントスタック操作系コマンド
  vim.api.nvim_create_user_command("ClaudeSubmit", function() M.submit("claude") end,
    { desc = "Submit stacked Claude comments" })
  vim.api.nvim_create_user_command("CodexSubmit", function() M.submit("codex") end,
    { desc = "Submit stacked Codex comments" })
  vim.api.nvim_create_user_command("ClaudeClear", function() M.clear_comments("claude") end,
    { desc = "Clear Claude comment stack" })
  vim.api.nvim_create_user_command("CodexClear", function() M.clear_comments("codex") end,
    { desc = "Clear Codex comment stack" })
  vim.api.nvim_create_user_command("ClaudeList", function() M.list_comments("claude") end,
    { desc = "List Claude comments in quickfix" })
  vim.api.nvim_create_user_command("CodexList", function() M.list_comments("codex") end,
    { desc = "List Codex comments in quickfix" })
  vim.api.nvim_create_user_command("ClaudeDelete", function() M.delete_comment_at_cursor("claude") end,
    { desc = "Delete Claude comment at cursor line" })
  vim.api.nvim_create_user_command("CodexDelete", function() M.delete_comment_at_cursor("codex") end,
    { desc = "Delete Codex comment at cursor line" })

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

  -- キーマップ: コメントスタック操作
  vim.keymap.set("n", "<leader>aS", "<Cmd>ClaudeSubmit<CR>",
    vim.tbl_extend("force", map_opts, { desc = "Submit Claude comment stack" }))
  vim.keymap.set("n", "<leader>aX", "<Cmd>ClaudeClear<CR>",
    vim.tbl_extend("force", map_opts, { desc = "Clear Claude comment stack" }))
  vim.keymap.set("n", "<leader>aL", "<Cmd>ClaudeList<CR>",
    vim.tbl_extend("force", map_opts, { desc = "List Claude comments" }))
  vim.keymap.set("n", "<leader>xS", "<Cmd>CodexSubmit<CR>",
    vim.tbl_extend("force", map_opts, { desc = "Submit Codex comment stack" }))
  vim.keymap.set("n", "<leader>xX", "<Cmd>CodexClear<CR>",
    vim.tbl_extend("force", map_opts, { desc = "Clear Codex comment stack" }))
  vim.keymap.set("n", "<leader>xL", "<Cmd>CodexList<CR>",
    vim.tbl_extend("force", map_opts, { desc = "List Codex comments" }))
  vim.keymap.set("n", "<leader>ad", "<Cmd>ClaudeDelete<CR>",
    vim.tbl_extend("force", map_opts, { desc = "Delete Claude comment at cursor line" }))
  vim.keymap.set("n", "<leader>xd", "<Cmd>CodexDelete<CR>",
    vim.tbl_extend("force", map_opts, { desc = "Delete Codex comment at cursor line" }))
end

return M
