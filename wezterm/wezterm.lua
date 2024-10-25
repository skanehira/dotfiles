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
  { key = 't', mods = 'CMD',        action = action.SpawnTab 'DefaultDomain' },
  { key = 'w', mods = 'CMD',        action = wezterm.action.CloseCurrentTab { confirm = true } },
  { key = "[", mods = "CMD|SHIFT",  action = wezterm.action.ActivateCopyMode },
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
  font_size = 16,
  adjust_window_size_when_changing_font_size = false,
  disable_default_key_bindings = true,
  -- leader = { key="s", mods="CTRL" },
  keys = keys,
  window_padding = {
    left = 5,
    right = 0,
    bottom = 0,
    top = 0,
  },
  enable_scroll_bar = false,
  front_end = "WebGpu",
  -- タイトルバーを非表示
  window_decorations = "RESIZE",
  -- タブが一つの時は非表示
  hide_tab_bar_if_only_one_tab = true,
  -- ウィンドウの透過
  window_background_opacity = 0.8,
  -- ウィンドウの背景のぼかし
  macos_window_background_blur = 20,
  -- タブバーの透過
  window_frame = {
    inactive_titlebar_bg = "none",
    active_titlebar_bg = "none",
  },
  -- タブバーの表示
  show_tabs_in_tab_bar = true,
  -- タブバーを背景色に合わせる
  window_background_gradient = {
    colors = { "#000000" },
  },
  -- タブの追加ボタンを非表示
  show_new_tab_button_in_tab_bar = false,
  -- タブの閉じるボタンを非表示
  show_close_tab_button_in_tabs = false,
  colors = {
    tab_bar = {
      inactive_tab_edge = "none",
    },
  }
}

-- タブの形をカスタマイズ
-- タブの左側の装飾
local SOLID_LEFT_ARROW = wezterm.nerdfonts.ple_lower_right_triangle
-- タブの右側の装飾
local SOLID_RIGHT_ARROW = wezterm.nerdfonts.ple_upper_left_triangle

wezterm.on("format-tab-title", function(tab, _, _, _, _, max_width)
  local background = "#5c6d74"
  local edge_background = "none"
  if tab.is_active then
    background = "#ae8b2d"
  end
  local edge_foreground = background
  local title = " " .. wezterm.truncate_right(tab.active_pane.title, max_width - 1) .. " "
  return {
    { Background = { Color = edge_background } },
    { Foreground = { Color = edge_foreground } },
    { Text = title },
  }
end)

return config
