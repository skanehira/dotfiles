local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
local utils = require('my/utils')

if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end

---@diagnostic disable-next-line: undefined-field
vim.opt.rtp:prepend(lazypath)

local ignore_files = {
  'disable.lua',
  'lazy.lua'
}

local function require_plugins(directory)
  local function scan_directory(dir)
    local handle = vim.uv.fs_scandir(dir)
    if not handle then
      return {}
    end

    local plugins = {}

    while true do
      local name, type = vim.uv.fs_scandir_next(handle)
      if not name then break end

      local full_path = dir .. "/" .. name

      if type == "file" and name:match("%.lua$") then
        if vim.tbl_contains(ignore_files, name) then
          goto continue
        end
        local plugin_path = utils.remove_before(full_path, 'my/plugins'):gsub("%.lua$", "")
        table.insert(plugins, require(plugin_path))
      elseif type == "directory" then
        for _, value in ipairs(scan_directory(full_path)) do
          table.insert(plugins, value)
        end
      end
      ::continue::
    end

    return plugins
  end

  return scan_directory(directory)
end

local plugins_path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ':h')
local plugins = require_plugins(plugins_path)

require("lazy").setup(plugins)
