local M = {}

local function parse_table_row(line)
  local cells = {}
  for cell in line:gmatch("|([^|]+)") do
    table.insert(cells, vim.fn.trim(cell))
  end
  return cells
end

local function is_separator_row(cells)
  if #cells == 0 then
    return false
  end
  for _, cell in ipairs(cells) do
    if not cell:match("^[-:]+$") then
      return false
    end
  end
  return true
end

local function pad_cell(text, width)
  local display_width = vim.fn.strdisplaywidth(text)
  local padding = width - display_width
  return text .. string.rep(" ", padding)
end

local function is_table_row(line)
  return line:match("^%s*|") ~= nil
end

local function format_table(lines)
  local rows = {}
  local non_table_lines = {}

  for i, line in ipairs(lines) do
    if is_table_row(line) then
      local cells = parse_table_row(line)
      if is_separator_row(cells) then
        table.insert(rows, { separator = true, cells = cells, index = i })
      else
        table.insert(rows, { separator = false, cells = cells, index = i })
      end
    else
      non_table_lines[i] = line
    end
  end

  if #rows == 0 then
    return lines
  end

  local col_count = 0
  for _, row in ipairs(rows) do
    col_count = math.max(col_count, #row.cells)
  end

  if col_count == 0 then
    return lines
  end

  local col_widths = {}
  for i = 1, col_count do
    col_widths[i] = 0
  end

  for _, row in ipairs(rows) do
    if not row.separator then
      for i, cell in ipairs(row.cells) do
        col_widths[i] = math.max(col_widths[i], vim.fn.strdisplaywidth(cell))
      end
    end
  end

  local formatted = {}
  local row_idx = 1
  for i = 1, #lines do
    if non_table_lines[i] then
      table.insert(formatted, non_table_lines[i])
    elseif row_idx <= #rows then
      local row = rows[row_idx]
      if row.separator then
        local sep_parts = {}
        for j = 1, col_count do
          table.insert(sep_parts, string.rep("-", col_widths[j]))
        end
        table.insert(formatted, "| " .. table.concat(sep_parts, " | ") .. " |")
      else
        local padded_cells = {}
        for j = 1, col_count do
          local cell = row.cells[j] or ""
          table.insert(padded_cells, pad_cell(cell, col_widths[j]))
        end
        table.insert(formatted, "| " .. table.concat(padded_cells, " | ") .. " |")
      end
      row_idx = row_idx + 1
    end
  end

  return formatted
end

function M.format_markdown_tables(bufnr)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "markdown")
  if not ok or not parser then
    return
  end

  local query_ok, query = pcall(vim.treesitter.query.parse, "markdown", "(pipe_table) @table")
  if not query_ok or not query then
    return
  end

  local tree = parser:parse()[1]
  if not tree then
    return
  end
  local root = tree:root()

  local tables = {}
  for id, node, _ in query:iter_captures(root, bufnr, 0, -1) do
    if query.captures[id] == "table" then
      table.insert(tables, node)
    end
  end

  for i = #tables, 1, -1 do
    local node = tables[i]
    local start_row, _, end_row, _ = node:range()
    local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
    local formatted = format_table(lines)
    vim.api.nvim_buf_set_lines(bufnr, start_row, end_row + 1, false, formatted)
  end
end

function M.setup()
  vim.api.nvim_create_autocmd("BufWritePre", {
    pattern = { "*.md", "*.markdown" },
    callback = function(args)
      M.format_markdown_tables(args.buf)
    end,
    group = vim.api.nvim_create_augroup("markdownTableFormat", { clear = true }),
  })
end

return M
