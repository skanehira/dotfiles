---@param array string[]
---@param func functionType
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

return {
  keymaps = keymaps,
  array_map = array_map,
}
