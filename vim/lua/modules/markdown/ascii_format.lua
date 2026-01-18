local M = {}

-- 罫線文字の定義（UTF-8で各3バイト）
local BORDER_CHARS = {
  TOP_LEFT = "┌",
  TOP_RIGHT = "┐",
  BOTTOM_LEFT = "└",
  BOTTOM_RIGHT = "┘",
  HORIZONTAL = "─",
  VERTICAL = "│",
  T_LEFT = "├",
  T_RIGHT = "┤",
}

-- 行の先頭文字を取得（UTF-8対応）
local function get_first_char(line)
  return vim.fn.strcharpart(line, 0, 1)
end

-- 行の末尾文字を取得（UTF-8対応）
local function get_last_char(line)
  local len = vim.fn.strchars(line)
  return vim.fn.strcharpart(line, len - 1, 1)
end

-- 枠線行（上辺、中間、下辺）かどうかを判定
local function is_box_border(line)
  local first = get_first_char(line)
  local last = get_last_char(line)

  -- 上辺: ┌─┐
  if first == BORDER_CHARS.TOP_LEFT and last == BORDER_CHARS.TOP_RIGHT then
    return true
  end
  -- 中間: ├─┤
  if first == BORDER_CHARS.T_LEFT and last == BORDER_CHARS.T_RIGHT then
    return true
  end
  -- 下辺: └─┘
  if first == BORDER_CHARS.BOTTOM_LEFT and last == BORDER_CHARS.BOTTOM_RIGHT then
    return true
  end

  return false
end

-- コンテンツ行（│...│）かどうかを判定
local function is_content_row(line)
  local first = get_first_char(line)
  local last = get_last_char(line)
  return first == BORDER_CHARS.VERTICAL and last == BORDER_CHARS.VERTICAL
end

-- 枠線文字を含むかどうかを判定
local function has_box_chars(line)
  for _, char in pairs(BORDER_CHARS) do
    if line:find(char, 1, true) then
      return true
    end
  end
  return false
end

-- 行の表示幅を取得
local function get_display_width(line)
  return vim.fn.strdisplaywidth(line)
end

-- コンテンツ行の必要幅を計算（│ + 中身(右トリム) + スペース1つ + │）
local function get_content_required_width(line)
  if not is_content_row(line) then
    return 0
  end
  -- 先頭と末尾の│を除いた中身を取得
  local len = vim.fn.strchars(line)
  local content = vim.fn.strcharpart(line, 1, len - 2)
  if not content or content == "" then
    return 0
  end
  local content_rtrimmed = content:gsub("%s+$", "")
  -- │ + 中身 + 最低1スペース + │
  return vim.fn.strdisplaywidth(content_rtrimmed) + 3
end

-- 枠線行を指定幅に拡張
local function expand_border_row(line, target_width)
  local current_width = get_display_width(line)
  if current_width >= target_width then
    return line
  end

  local first = get_first_char(line)
  local last = get_last_char(line)

  -- 必要な─の数（表示幅ベース: target_width - 左右の枠線文字各1）
  local dash_count = target_width - 2

  if first == BORDER_CHARS.TOP_LEFT and last == BORDER_CHARS.TOP_RIGHT then
    return BORDER_CHARS.TOP_LEFT .. string.rep(BORDER_CHARS.HORIZONTAL, dash_count) .. BORDER_CHARS.TOP_RIGHT
  elseif first == BORDER_CHARS.T_LEFT and last == BORDER_CHARS.T_RIGHT then
    return BORDER_CHARS.T_LEFT .. string.rep(BORDER_CHARS.HORIZONTAL, dash_count) .. BORDER_CHARS.T_RIGHT
  elseif first == BORDER_CHARS.BOTTOM_LEFT and last == BORDER_CHARS.BOTTOM_RIGHT then
    return BORDER_CHARS.BOTTOM_LEFT .. string.rep(BORDER_CHARS.HORIZONTAL, dash_count) .. BORDER_CHARS.BOTTOM_RIGHT
  end

  return line
end

-- コンテンツ行をフォーマット
local function format_content_row(line, target_width)
  if not is_content_row(line) then
    return line
  end

  -- 先頭の│と末尾の│を除いた中身を取得（UTF-8対応）
  local len = vim.fn.strchars(line)
  local content = vim.fn.strcharpart(line, 1, len - 2)
  if not content or content == "" then
    return line
  end

  -- 右端のスペースを除去した中身を取得（左側のスペースは維持）
  local content_rtrimmed = content:gsub("%s+$", "")

  -- 現在の表示幅を計算
  local current_width = vim.fn.strdisplaywidth(content_rtrimmed)

  -- 期待される中身の幅（target_width - 2 for │ on both sides）
  local expected_content_width = target_width - 2

  -- 必要な右パディング
  local right_padding = expected_content_width - current_width
  if right_padding < 0 then
    -- コンテンツが幅を超える場合はそのまま返す
    return line
  end

  -- 新しい行を構築（左側は元のまま、右側だけ調整）
  local new_line = BORDER_CHARS.VERTICAL .. content_rtrimmed .. string.rep(" ", right_padding) .. BORDER_CHARS.VERTICAL

  return new_line
end

-- ASCII図ブロックを検出してフォーマット
local function format_ascii_box_block(lines, start_idx, end_idx)
  local block_lines = {}
  for i = start_idx, end_idx do
    table.insert(block_lines, lines[i])
  end

  -- 枠線行の幅を検出
  local border_width = 0
  for _, line in ipairs(block_lines) do
    if is_box_border(line) then
      local width = get_display_width(line)
      if width > border_width then
        border_width = width
      end
    end
  end

  -- コンテンツ行の必要幅を検出
  local content_max_width = 0
  for _, line in ipairs(block_lines) do
    local required = get_content_required_width(line)
    if required > content_max_width then
      content_max_width = required
    end
  end

  -- 目標幅は枠線幅とコンテンツ必要幅の大きい方
  local target_width = math.max(border_width, content_max_width)

  if target_width == 0 then
    return block_lines
  end

  -- 各行をフォーマット
  local formatted = {}
  for _, line in ipairs(block_lines) do
    if is_box_border(line) then
      table.insert(formatted, expand_border_row(line, target_width))
    elseif is_content_row(line) then
      table.insert(formatted, format_content_row(line, target_width))
    else
      table.insert(formatted, line)
    end
  end

  return formatted
end

-- fenced code block内のASCII図を検出
local function find_code_blocks(bufnr)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "markdown")
  if not ok or not parser then
    return {}
  end

  local query_ok, query = pcall(vim.treesitter.query.parse, "markdown", "(fenced_code_block) @code")
  if not query_ok or not query then
    return {}
  end

  local tree = parser:parse()[1]
  if not tree then
    return {}
  end
  local root = tree:root()

  local code_blocks = {}
  for id, node, _ in query:iter_captures(root, bufnr, 0, -1) do
    if query.captures[id] == "code" then
      local start_row, _, end_row, _ = node:range()
      table.insert(code_blocks, { start_row = start_row, end_row = end_row })
    end
  end

  return code_blocks
end

-- ASCII図ブロックを検出（連続する罫線行をグループ化）
local function find_ascii_boxes_in_range(lines, start_offset)
  local boxes = {}
  local current_box_start = nil

  for i, line in ipairs(lines) do
    if has_box_chars(line) then
      if current_box_start == nil then
        current_box_start = i
      end
    else
      if current_box_start ~= nil then
        table.insert(boxes, {
          start_idx = current_box_start,
          end_idx = i - 1,
          offset = start_offset
        })
        current_box_start = nil
      end
    end
  end

  -- 最後のブロックを処理
  if current_box_start ~= nil then
    table.insert(boxes, {
      start_idx = current_box_start,
      end_idx = #lines,
      offset = start_offset
    })
  end

  return boxes
end

function M.format_ascii_boxes(bufnr)
  local code_blocks = find_code_blocks(bufnr)

  if #code_blocks == 0 then
    return
  end

  -- 逆順で処理（行番号がずれないように）
  for i = #code_blocks, 1, -1 do
    local block = code_blocks[i]
    -- fenced_code_blockは```行を含むので、中身だけを取得
    local lines = vim.api.nvim_buf_get_lines(bufnr, block.start_row + 1, block.end_row, false)

    -- ASCII図ブロックを検出
    local ascii_boxes = find_ascii_boxes_in_range(lines, block.start_row + 1)

    -- 逆順で処理
    for j = #ascii_boxes, 1, -1 do
      local box = ascii_boxes[j]
      local box_lines = {}
      for k = box.start_idx, box.end_idx do
        table.insert(box_lines, lines[k])
      end

      local formatted = format_ascii_box_block(box_lines, 1, #box_lines)

      -- バッファの実際の行番号に変換
      local buf_start = box.offset + box.start_idx - 1
      local buf_end = box.offset + box.end_idx

      vim.api.nvim_buf_set_lines(bufnr, buf_start, buf_end, false, formatted)
    end
  end
end

function M.setup()
  vim.api.nvim_create_autocmd("BufWritePre", {
    pattern = { "*.md", "*.markdown" },
    callback = function(args)
      M.format_ascii_boxes(args.buf)
    end,
    group = vim.api.nvim_create_augroup("asciiBoxFormat", { clear = true }),
  })
end

return M
