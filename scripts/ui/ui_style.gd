class_name UIStyle
extends RefCounted
## Shared look for the placeholder UI (ink black panels, paper white text, vermilion accent).

const INK := Color(0.06, 0.06, 0.07, 0.86)
const PAPER := Color(0.93, 0.9, 0.84)
const MUTED := Color(0.66, 0.63, 0.58)
const VERMILION := Color(0.78, 0.2, 0.13)
const GOLD := Color(0.84, 0.68, 0.3)


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 17
	var panel := StyleBoxFlat.new()
	panel.bg_color = INK
	panel.border_color = Color(VERMILION, 0.9)
	panel.border_width_left = 3
	panel.content_margin_left = 22
	panel.content_margin_right = 22
	panel.content_margin_top = 18
	panel.content_margin_bottom = 18
	t.set_stylebox("panel", "PanelContainer", panel)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.16, 0.15, 0.15, 0.95)
		if state == "hover" or state == "focus":
			sb.bg_color = Color(0.3, 0.12, 0.09, 0.95)
		elif state == "pressed":
			sb.bg_color = VERMILION
		elif state == "disabled":
			sb.bg_color = Color(0.12, 0.12, 0.12, 0.6)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		sb.corner_radius_top_left = 2
		sb.corner_radius_bottom_right = 2
		t.set_stylebox(state, "Button", sb)
	t.set_color("font_color", "Button", PAPER)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_color", "Label", PAPER)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.05, 0.05, 0.05, 0.75)
	bar_bg.border_color = Color(0, 0, 0, 0.9)
	bar_bg.set_border_width_all(1)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	return t


static func bar_fill(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	return sb


static func label(text: String, size: int = 17, color: Color = PAPER) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
