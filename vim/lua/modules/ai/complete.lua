-- AI入力バッファ用のtelescope補完
-- <C-f>: ファイル検索
-- <C-l>: コマンド・スキル検索

local M = {}

-- キャッシュ（コマンドとスキルは変更が少ないためメモリに保持）
local cache = {
  commands = nil,
  skills = nil,
}

-- YAMLフロントマターをパース（簡易実装）
-- @param content string ファイル内容
-- @return table フロントマターのキー・値
local function parse_frontmatter(content)
  local frontmatter = content:match("^%-%-%-\n(.-)\n%-%-%-")
  if not frontmatter then
    return {}
  end

  local result = {}
  for line in frontmatter:gmatch("[^\n]+") do
    local key, value = line:match("^([%w-]+):%s*(.+)$")
    if key and value then
      -- クォートを除去
      value = value:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
      result[key] = value
    end
  end
  return result
end

-- コマンド一覧を取得（キャッシュあり）
-- @return table { {name = "/ask", description = "..."}, ... }
local function get_commands()
  if cache.commands then
    return cache.commands
  end

  cache.commands = {}
  local dirs = {
    vim.fn.expand("~/.claude/commands"),
    vim.fn.getcwd() .. "/.claude/commands",
  }

  for _, dir in ipairs(dirs) do
    local files = vim.fn.glob(dir .. "/*.md", false, true)
    for _, file in ipairs(files) do
      local name = vim.fn.fnamemodify(file, ":t:r")
      local lines = vim.fn.readfile(file)
      local fm = parse_frontmatter(table.concat(lines, "\n"))
      table.insert(cache.commands, {
        name = "/" .. name,
        description = fm.description or "",
        type = "command",
      })
    end
  end
  return cache.commands
end

-- スキル一覧を取得（user-invocable: trueのみ、キャッシュあり）
-- @return table { {name = "/impl", description = "..."}, ... }
local function get_skills()
  if cache.skills then
    return cache.skills
  end

  cache.skills = {}
  local dirs = {
    vim.fn.expand("~/.claude/skills"),
    vim.fn.getcwd() .. "/.claude/skills",
  }

  for _, dir in ipairs(dirs) do
    local skill_files = vim.fn.glob(dir .. "/*/SKILL.md", false, true)
    for _, file in ipairs(skill_files) do
      local lines = vim.fn.readfile(file)
      local fm = parse_frontmatter(table.concat(lines, "\n"))
      -- user-invocable: true のもののみ
      if fm["user-invocable"] == "true" then
        -- nameがない場合はディレクトリ名を使用
        local skill_name = fm.name
        if not skill_name or skill_name == "" then
          skill_name = vim.fn.fnamemodify(file, ":h:t")
        end
        table.insert(cache.skills, {
          name = "/" .. skill_name,
          description = fm.description or "",
          type = "skill",
        })
      end
    end
  end
  return cache.skills
end

-- キャッシュクリア
function M.clear_cache()
  cache.commands = nil
  cache.skills = nil
end

-- カーソル位置にテキストを挿入
-- @param text string 挿入するテキスト
local function insert_at_cursor(text)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  local new_line = line:sub(1, col) .. text .. line:sub(col + 1)
  vim.api.nvim_set_current_line(new_line)
  vim.api.nvim_win_set_cursor(0, { row, col + #text })
end

-- ファイル検索（telescope）
function M.pick_file()
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  pickers
    .new({}, {
      prompt_title = "Insert File Path",
      finder = finders.new_oneshot_job({ "rg", "--files" }, {}),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr, map)
        local function restore_insert_mode()
          vim.schedule(function()
            vim.cmd("startinsert")
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Right>", true, false, true), "n", false)
          end)
        end

        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            insert_at_cursor("@" .. selection[1])
          end
          restore_insert_mode()
        end)

        actions.close:enhance({
          post = restore_insert_mode,
        })

        map("i", "<C-c>", function()
          actions.close(prompt_bufnr)
        end)

        return true
      end,
    })
    :find()
end

-- コマンド・スキル検索（telescope）
function M.pick_command()
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  -- コマンドとスキルを結合
  local items = {}
  for _, cmd in ipairs(get_commands()) do
    table.insert(items, cmd)
  end
  for _, skill in ipairs(get_skills()) do
    table.insert(items, skill)
  end

  pickers
    .new({}, {
      prompt_title = "Insert Command/Skill",
      finder = finders.new_table({
        results = items,
        entry_maker = function(entry)
          return {
            value = entry,
            display = string.format("%s  %s", entry.name, entry.description),
            ordinal = entry.name .. " " .. entry.description,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr, map)
        local function restore_insert_mode()
          vim.schedule(function()
            vim.cmd("startinsert")
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Right>", true, false, true), "n", false)
          end)
        end

        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            insert_at_cursor(selection.value.name)
          end
          restore_insert_mode()
        end)

        actions.close:enhance({
          post = restore_insert_mode,
        })

        map("i", "<C-c>", function()
          actions.close(prompt_bufnr)
        end)

        return true
      end,
    })
    :find()
end

return M
