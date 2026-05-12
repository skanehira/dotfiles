-- AIツール（Claude/Codex）向けコメントスタックモジュール
-- PRレビュー風にコメントをローカルに溜め、Submitで一括送信する
-- 1スレッド = 1メッセージ。同じ範囲を再度開くと既存メッセージをロードして編集する設計
-- 範囲指定（ビジュアル選択）のコメントのみを管理し、ファイル全体コメントは扱わない

local M = {}

-- ツール別の独立ストア
-- 構造:
--   store[tool][file_path] = {
--     next_id = number,
--     threads = {
--       { id, start_line, end_line, message = "..." },
--     },
--   }
local store = {
  claude = {},
  codex = {},
}

-- ツール別の extmark namespace
local ns = {
  claude = nil,
  codex = nil,
}

local TOOLS = { "claude", "codex" }

-- コメント絵文字（U+1F4AC, speech balloon）。emoji は 2 セル幅で sign_text 制約を満たす
local SIGN_ICON = "💬"

-- gitsigns 風の範囲行マーカー（U+2503 BOX DRAWINGS HEAVY VERTICAL + 半角スペースで 2 セル幅）
local BAR_ICON = "┃ "

-- ハイライトグループ定義（colorscheme 変更後も再適用される）
-- DiagnosticSignInfo にlinkすると一部テーマで透明になり見えないので明示色を指定
local function define_highlights()
  vim.api.nvim_set_hl(0, "AICommentSign", { default = true, fg = "#FF9E64" })
  vim.api.nvim_set_hl(0, "AICommentBar", { default = true, fg = "#FF9E64" })
end

-- ツール名のバリデーション
local function assert_tool(tool)
  if not store[tool] then
    error(string.format("Unknown AI tool: %s", tostring(tool)))
  end
end

-- パスを :p で正規化（store のキーと比較で揺れを防ぐ）
local function normalize_path(path)
  if not path or path == "" then
    return path
  end
  return vim.fn.fnamemodify(path, ":p")
end

-- 全可視ウィンドウのバッファを refresh（path 比較に依存しない確実な手段）
local function refresh_all_visible()
  local seen = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local bufnr = vim.api.nvim_win_get_buf(win)
    if not seen[bufnr] then
      seen[bufnr] = true
      M.refresh_buffer(bufnr)
    end
  end
end

-- ファイル単位のスレッドコンテナを取得（無ければ作成）
local function ensure_file(tool, file_path)
  local tool_store = store[tool]
  if not tool_store[file_path] then
    tool_store[file_path] = { next_id = 1, threads = {} }
  end
  return tool_store[file_path]
end

-- 同一 (start_line, end_line) のスレッドの index を返す
local function find_thread_index(file, start_line, end_line)
  for i, t in ipairs(file.threads) do
    if t.start_line == start_line and t.end_line == end_line then
      return i
    end
  end
  return nil
end

-- 既存メッセージを取得（編集時のプリロード用）
-- @return string|nil 既存コメント本文
function M.get(tool, file_path, start_line, end_line)
  assert_tool(tool)
  file_path = normalize_path(file_path)
  local file = store[tool][file_path]
  if not file then
    return nil
  end
  local i = find_thread_index(file, start_line, end_line)
  if not i then
    return nil
  end
  return file.threads[i].message
end

-- メッセージを保存（既存スレッドは上書き、無ければ新規）
-- @return number thread_id, boolean was_new
function M.set(tool, file_path, start_line, end_line, message)
  assert_tool(tool)
  file_path = normalize_path(file_path)
  local file = ensure_file(tool, file_path)
  local i = find_thread_index(file, start_line, end_line)
  local id, was_new
  if i then
    file.threads[i].message = message
    id, was_new = file.threads[i].id, false
  else
    local thread = {
      id = file.next_id,
      start_line = start_line,
      end_line = end_line,
      message = message,
    }
    file.next_id = file.next_id + 1
    table.insert(file.threads, thread)
    id, was_new = thread.id, true
  end
  refresh_all_visible()
  return id, was_new
end

-- スレッドを削除
function M.delete(tool, file_path, start_line, end_line)
  assert_tool(tool)
  file_path = normalize_path(file_path)
  local file = store[tool][file_path]
  if not file then
    return false
  end
  local i = find_thread_index(file, start_line, end_line)
  if not i then
    return false
  end
  table.remove(file.threads, i)
  if #file.threads == 0 then
    store[tool][file_path] = nil
  end
  refresh_all_visible()
  return true
end

-- 指定行を含むスレッドの中で最も狭い範囲のものを返す
-- 同じ行に複数スレッドがネストしている場合、内側（狭い範囲）を優先
-- @return table|nil { start_line, end_line, message, id } 形のコピー
function M.find_at_line(tool, file_path, line)
  assert_tool(tool)
  file_path = normalize_path(file_path)
  local file = store[tool][file_path]
  if not file then
    return nil
  end
  local best
  local best_size = math.huge
  for _, t in ipairs(file.threads) do
    if line >= t.start_line and line <= t.end_line then
      local size = t.end_line - t.start_line
      if size < best_size then
        best = t
        best_size = size
      end
    end
  end
  if not best then
    return nil
  end
  return {
    id = best.id,
    start_line = best.start_line,
    end_line = best.end_line,
    message = best.message,
  }
end

-- 指定行を含むスレッドをすべて削除
-- @return number 削除した件数
function M.delete_at_line(tool, file_path, line)
  assert_tool(tool)
  file_path = normalize_path(file_path)
  local file = store[tool][file_path]
  if not file then
    return 0
  end
  local removed = 0
  for i = #file.threads, 1, -1 do
    local t = file.threads[i]
    if line >= t.start_line and line <= t.end_line then
      table.remove(file.threads, i)
      removed = removed + 1
    end
  end
  if #file.threads == 0 then
    store[tool][file_path] = nil
  end
  if removed > 0 then
    refresh_all_visible()
  end
  return removed
end

-- ツール全体のスレッド一覧（file_path 付き、Submit/List 用）
function M.list(tool)
  assert_tool(tool)
  local result = {}
  for file_path, file in pairs(store[tool]) do
    for _, t in ipairs(file.threads) do
      table.insert(result, {
        file_path = file_path,
        id = t.id,
        start_line = t.start_line,
        end_line = t.end_line,
        message = t.message,
      })
    end
  end
  -- file_path → start_line の順でソート（安定した送信順）
  table.sort(result, function(a, b)
    if a.file_path ~= b.file_path then
      return a.file_path < b.file_path
    end
    if a.start_line ~= b.start_line then
      return a.start_line < b.start_line
    end
    return a.id < b.id
  end)
  return result
end

-- スタック数
function M.count(tool)
  assert_tool(tool)
  local n = 0
  for _, file in pairs(store[tool]) do
    n = n + #file.threads
  end
  return n
end

-- ツールのスタック全削除 + 全バッファの extmark クリア
function M.clear(tool)
  assert_tool(tool)
  store[tool] = {}
  if ns[tool] then
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_clear_namespace(bufnr, ns[tool], 0, -1)
      end
    end
  end
end

-- 送信用文字列に整形
-- @return string|nil スタックが空のとき nil
function M.format_for_submit(tool)
  assert_tool(tool)
  local threads = M.list(tool)
  if #threads == 0 then
    return nil
  end

  local lines = { "以下のレビューコメントについて対応をお願いします。", "" }
  for _, t in ipairs(threads) do
    local header
    if t.start_line == t.end_line then
      header = string.format("## @%s#L%d", t.file_path, t.start_line)
    else
      header = string.format("## @%s#L%d-%d", t.file_path, t.start_line, t.end_line)
    end
    table.insert(lines, header)
    -- メッセージ本文をそのまま展開（複数行も維持）
    for line in (t.message .. "\n"):gmatch("([^\n]*)\n") do
      table.insert(lines, line)
    end
    if lines[#lines] ~= "" then
      table.insert(lines, "")
    end
  end
  return table.concat(lines, "\n")
end

-- バッファに対して各ツールの extmark を貼り直す
function M.refresh_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local raw_name = vim.api.nvim_buf_get_name(bufnr)
  if raw_name == "" then
    return
  end
  local file_path = normalize_path(raw_name)
  local buf_lines = vim.api.nvim_buf_line_count(bufnr)

  -- signcolumn が完全に無効だと sign 自体表示されないので一度だけ警告
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    if vim.wo[win].signcolumn == "no" then
      vim.notify_once(
        "AI コメント: signcolumn=no のため sign アイコンが表示されません。:set signcolumn=auto:1 を検討してください",
        vim.log.levels.WARN
      )
    end
  end

  for _, tool in ipairs(TOOLS) do
    local nsid = ns[tool]
    if nsid then
      vim.api.nvim_buf_clear_namespace(bufnr, nsid, 0, -1)
      local file = store[tool][file_path]
      if file then
        -- start_line ごとにスレッドをグループ化（同一行に複数スレッドがあるケース）
        local by_start = {}
        for _, t in ipairs(file.threads) do
          by_start[t.start_line] = by_start[t.start_line] or {}
          table.insert(by_start[t.start_line], t)
        end

        -- 1) すべての範囲行に縦棒 sign を貼る（gitsigns 風）
        for _, t in ipairs(file.threads) do
          for line = t.start_line, t.end_line do
            local row = math.max(0, math.min(buf_lines - 1, line - 1))
            pcall(vim.api.nvim_buf_set_extmark, bufnr, nsid, row, 0, {
              sign_text = BAR_ICON,
              sign_hl_group = "AICommentBar",
              priority = 10,
            })
          end
        end

        -- 2) 開始行は絵文字（複数スレッドはバッジ）で上書き。priority を高くして縦棒に勝たせる
        for start_line, ts in pairs(by_start) do
          local count = #ts
          local sign_text
          if count == 1 then
            sign_text = SIGN_ICON
          elseif count < 10 then
            sign_text = tostring(count) .. " "
          else
            sign_text = "+ "
          end
          local row = math.max(0, start_line - 1)
          pcall(vim.api.nvim_buf_set_extmark, bufnr, nsid, row, 0, {
            sign_text = sign_text,
            sign_hl_group = "AICommentSign",
            priority = 20,
          })
        end
      end
    end
  end
end

-- 初期化（namespace 確保、autocmd 登録、ハイライト定義）
function M.setup()
  ns.claude = vim.api.nvim_create_namespace("ai_comments_claude")
  ns.codex = vim.api.nvim_create_namespace("ai_comments_codex")
  define_highlights()

  local group = vim.api.nvim_create_augroup("AICommentsRefresh", { clear = true })
  vim.api.nvim_create_autocmd({ "BufWinEnter", "BufReadPost" }, {
    group = group,
    callback = function(args)
      M.refresh_buffer(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = define_highlights,
  })
end

return M
