---@param array string[]
local function array_map(array, func)
  local new_array = {}
  for _, v in ipairs(array) do
    table.insert(new_array, func(v))
  end
  return new_array
end

local map = function(mode, lhs, rhs, opt)
  vim.keymap.set(mode, lhs, rhs, opt or { silent = true })
end

local keymaps = {
  map = map,
}

for _, mode in pairs({ 'n', 'v', 'i', 'o', 'c', 't', 'x', 't' }) do
  keymaps[mode .. 'map'] = function(lhs, rhs, opt)
    map(mode, lhs, rhs, opt)
  end
end


local function remove_before(text, pattern)
  local start_pos = text:find(pattern)
  if start_pos then
    return text:sub(start_pos)
  else
    return text
  end
end


local function get_open_command()
  if vim.fn.has("mac") == 1 then
    return "open"
  elseif vim.fn.has("unix") == 1 then
    return "xdg-open"
  elseif vim.fn.has("win32") == 1 then
    return "start"
  else
    return ""
  end
end

return {
  remove_before = remove_before,
  keymaps = keymaps,
  array_map = array_map,
  get_open_command = get_open_command,
}
