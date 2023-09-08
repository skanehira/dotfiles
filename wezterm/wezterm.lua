local wezterm = require 'wezterm';

wezterm.on('window-maximize', function(window, _)
  window:maximize()
end)

local action = wezterm.action

local keys = {
  { key = "c", mods = "CMD",        action = action.CopyTo 'Clipboard' },
  { key = 'v', mods = 'CMD',        action = action.PasteFrom 'Clipboard' },
  { key = ";", mods = "CMD",        action = action.IncreaseFontSize },
  { key = "-", mods = "CMD",        action = action.DecreaseFontSize },
  { key = " ", mods = "CTRL",       action = action.HideApplication },
  { key = "q", mods = "CMD",        action = action.QuitApplication },
  -- C-q を2回押さないと行けない問題を回避す
  { key = 'q', mods = 'CTRL',       action = action { SendString = '\x11' } },
  { key = 'm', mods = 'SHIFT|CTRL', action = action.EmitEvent 'window-maximize' },
  -- { key = "¥", mods = "CMD", action=action{SplitHorizontal={domain="CurrentPaneDomain"}}},
  -- { key = "-", mods = "CMD", action=action{SplitVertical={domain="CurrentPaneDomain"}}},
  -- { key = "h", mods = "LEADER", action=action{AdjustPaneSize={"Left", 5}}},
  -- { key = "j", mods = "LEADER", action=action{AdjustPaneSize={"Down", 5}}},
  -- { key = "k", mods = "LEADER", action=action{AdjustPaneSize={"Up", 5}}},
  -- { key = "l", mods = "LEADER", action=action{AdjustPaneSize={"Right", 5}}},
  -- { key = "D", mods="CTRL|SHIFT", action=action{DetachDomain="CurrentPaneDomain"}},
}

-- ref: https://wezfurlong.org/wezterm/config/lua/keyassignment/ActivateTab.html
for i = 1, 9 do
  -- CTRL+ALT + number to activate that tab
  table.insert(keys, {
    key = tostring(i),
    mods = "CMD",
    action = action.ActivateTab(i - 1),
  })
end

local config = {
  audible_bell = "Disabled",
  color_scheme = "iceberg-dark",
  font = wezterm.font("Cica"),
  macos_forward_to_ime_modifier_mask = "SHIFT|CTRL",
  font_size = 17,
  hide_tab_bar_if_only_one_tab = true,
  adjust_window_size_when_changing_font_size = false,
  disable_default_key_bindings = true,
  -- leader = { key="s", mods="CTRL" },
  window_decorations = "RESIZE",
  keys = keys,
  window_padding = {
    left = 5,
    right = 0,
    bottom = 0,
    top = 0,
  },
  enable_scroll_bar = false,
  front_end = "WebGpu",
}

return config
