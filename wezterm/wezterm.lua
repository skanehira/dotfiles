local wezterm = require 'wezterm';

wezterm.on('window-maximize', function(window, _)
  window:maximize()
end)

return {
	color_scheme = "iceberg-dark",
	font = wezterm.font("Cica"),
	font_size = 17,
	hide_tab_bar_if_only_one_tab = true,
	adjust_window_size_when_changing_font_size = false,
	disable_default_key_bindings = true,
	-- leader = { key="s", mods="CTRL" },
	window_decorations = "RESIZE",
	keys = {
		{ key = "c", mods = "CMD", action = wezterm.action.CopyTo 'Clipboard' },
		{ key = 'v', mods = 'CMD', action = wezterm.action.PasteFrom 'Clipboard' },
		{ key = ";", mods = "CMD", action = wezterm.action.IncreaseFontSize },
		{ key = "-", mods = "CMD", action = wezterm.action.DecreaseFontSize },
		{ key = " ", mods = "CTRL", action = wezterm.action.HideApplication },
		{ key = "q", mods = "CMD", action = wezterm.action.QuitApplication },
    -- C-q を2回押さないと行けない問題を回避するため
    { key = 'q', mods = 'CTRL', action = wezterm.action { SendString = '\x11' } },
    { key = 'm', mods = 'SHIFT|CTRL', action = wezterm.action.EmitEvent 'window-maximize' },
		-- { key = "¥", mods = "CMD", action=wezterm.action{SplitHorizontal={domain="CurrentPaneDomain"}}},
		-- { key = "-", mods = "CMD", action=wezterm.action{SplitVertical={domain="CurrentPaneDomain"}}},
		-- { key = "h", mods = "LEADER", action=wezterm.action{AdjustPaneSize={"Left", 5}}},
		-- { key = "j", mods = "LEADER", action=wezterm.action{AdjustPaneSize={"Down", 5}}},
		-- { key = "k", mods = "LEADER", action=wezterm.action{AdjustPaneSize={"Up", 5}}},
		-- { key = "l", mods = "LEADER", action=wezterm.action{AdjustPaneSize={"Right", 5}}},
		-- { key = "D", mods="CTRL|SHIFT", action=wezterm.action{DetachDomain="CurrentPaneDomain"}},
	},
  window_padding = {
    left = 5,
    right = 0,
    bottom = 0,
    top = 0,
  },
  enable_scroll_bar = false,
  front_end = "WebGpu",
}
