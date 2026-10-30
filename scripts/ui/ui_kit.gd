class_name UiKit
extends RefCounted
## 纯代码 UI 工具：统一深色主题、字体、常用容器与卡片。
## 不依赖任何第三方 UI 框架，全部使用 Godot Control 节点。

const ACCENT := Color("#87ceeb")
const BG := Color("#121419")
const PANEL := Color("#1c2029")
const PANEL_ALT := Color("#232833")
const TEXT := Color("#e6e9ef")
const MUTED := Color("#98a2b3")
const ERROR := Color("#ff7b72")
const WARN := Color("#e3b341")
const SUCCESS := Color("#7ee787")
const LINE := Color("#333a47")


static func make_theme() -> Theme:
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "Noto Sans SC",
		"Source Han Sans SC", "WenQuanYi Micro Hei", "WenQuanYi Zen Hei",
		"PingFang SC", "sans-serif",
	])
	theme.default_font = font
	theme.default_font_size = 15

	theme.set_stylebox("normal", "Button", _box(PANEL_ALT, 6, 12, 7, LINE))
	theme.set_stylebox("hover", "Button", _box(Color("#323a49"), 6, 12, 7, Color("#475063")))
	theme.set_stylebox("pressed", "Button", _box(Color("#171b23"), 6, 12, 7, ACCENT))
	theme.set_stylebox("disabled", "Button", _box(Color("#1a1e26"), 6, 12, 7, Color("#2a303c")))
	theme.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), 6, 8, 4, ACCENT))
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", ACCENT)
	theme.set_color("font_disabled_color", "Button", MUTED)
	theme.set_font_size("font_size", "Button", 14)

	theme.set_stylebox("normal", "LineEdit", _box(Color("#0e1116"), 5, 9, 5, LINE))
	theme.set_stylebox("focus", "LineEdit", _box(Color("#0e1116"), 5, 9, 5, ACCENT))
	theme.set_stylebox("read_only", "LineEdit", _box(Color("#151922"), 5, 9, 5, Color("#2b3140")))
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", Color("#6b7485"))
	theme.set_color("caret_color", "LineEdit", ACCENT)
	theme.set_color("selection_color", "LineEdit", Color(0.53, 0.81, 0.92, 0.30))

	theme.set_stylebox("normal", "OptionButton", _box(PANEL_ALT, 6, 10, 6, LINE))
	theme.set_stylebox("hover", "OptionButton", _box(Color("#323a49"), 6, 10, 6, Color("#475063")))
	theme.set_stylebox("pressed", "OptionButton", _box(Color("#171b23"), 6, 10, 6, ACCENT))
	theme.set_stylebox("focus", "OptionButton", _box(Color(0, 0, 0, 0), 6, 8, 4, ACCENT))
	theme.set_color("font_color", "OptionButton", TEXT)
	theme.set_color("font_hover_color", "OptionButton", Color.WHITE)
	theme.set_font_size("font_size", "OptionButton", 14)

	theme.set_stylebox("panel", "PanelContainer", _box(PANEL, 8, 0, 0, LINE))
	theme.set_stylebox("panel", "ItemList", _box(Color("#0e1116"), 6, 4, 4, LINE))
	theme.set_stylebox("selected", "ItemList", _box(Color(0.53, 0.81, 0.92, 0.22), 4, 2, 2, ACCENT))
	theme.set_stylebox("selected_focus", "ItemList", _box(Color(0.53, 0.81, 0.92, 0.30), 4, 2, 2, ACCENT))
	theme.set_stylebox("cursor", "ItemList", _box(Color(0, 0, 0, 0), 4, 2, 2, ACCENT))
	theme.set_stylebox("cursor_unfocused", "ItemList", _box(Color(0, 0, 0, 0), 4, 2, 2, Color("#475063")))
	theme.set_color("font_color", "ItemList", TEXT)
	theme.set_color("font_selected_color", "ItemList", Color.WHITE)
	theme.set_font_size("font_size", "ItemList", 14)

	theme.set_stylebox("background", "ProgressBar", _box(Color("#0d1015"), 5, 0, 0, Color("#2b3140")))
	theme.set_stylebox("fill", "ProgressBar", _box(ACCENT, 5, 0, 0, Color(0, 0, 0, 0)))
	theme.set_color("font_color", "ProgressBar", BG)
	theme.set_font_size("font_size", "ProgressBar", 11)

	theme.set_stylebox("panel", "TabContainer", _box(PANEL, 8, 8, 8, LINE))
	theme.set_color("font_selected_color", "TabContainer", ACCENT)
	theme.set_color("font_unselected_color", "TabContainer", MUTED)
	theme.set_font_size("font_size", "TabContainer", 14)

	theme.set_color("default_color", "RichTextLabel", TEXT)
	theme.set_font_size("normal_font_size", "RichTextLabel", 14)
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_color", "CheckBox", TEXT)
	theme.set_color("font_hover_color", "CheckBox", Color.WHITE)
	theme.set_color("font_pressed_color", "CheckBox", ACCENT)
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		theme.set_stylebox(state, "CheckBox", empty)
	theme.set_color("font_color", "TooltipLabel", TEXT)
	theme.set_stylebox("panel", "TooltipPanel", _box(Color("#10131a"), 6, 8, 6, LINE))
	return theme


static func _box(color: Color, radius: int, margin_h: int, margin_v: int, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	box.content_margin_left = margin_h
	box.content_margin_right = margin_h
	box.content_margin_top = margin_v
	box.content_margin_bottom = margin_v
	if border.a > 0.0:
		box.border_width_left = 1
		box.border_width_right = 1
		box.border_width_top = 1
		box.border_width_bottom = 1
		box.border_color = border
	return box


static func vbox(separation: int = 8) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


static func hbox(separation: int = 8) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


static func label(text: String, font_size: int = 15, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


static func wrapped_label(text: String, font_size: int = 13, color: Color = MUTED) -> Label:
	var l := label(text, font_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


const FxButtonScript = preload("res://scripts/ui/fx_button.gd")

static func button(text: String) -> Button:
	var b = FxButtonScript.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	return b


static func accent_button(text: String) -> Button:
	var b = FxButtonScript.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.is_primary = true
	var normal := _box(ACCENT, 6, 14, 8, Color("#a8dcef"))
	var hover := _box(Color("#a6e1f5"), 6, 14, 8, Color.WHITE)
	var pressed := _box(Color("#6fb9d4"), 6, 14, 8, Color.WHITE)
	for pair in [["normal", normal], ["hover", hover], ["pressed", pressed]]:
		b.add_theme_stylebox_override(pair[0], pair[1])
	b.add_theme_color_override("font_color", BG)
	b.add_theme_color_override("font_hover_color", BG)
	b.add_theme_color_override("font_pressed_color", BG)
	b.add_theme_font_size_override("font_size", 15)
	return b


static func spacer(expand: bool = true) -> Control:
	var c := Control.new()
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func card(padding: int = 12) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := _box(PANEL, 8, padding, padding, LINE)
	panel.add_theme_stylebox_override("panel", style)
	return panel


static func card_body(title: String) -> Dictionary:
	var panel := card(12)
	var box := vbox(8)
	panel.add_child(box)
	var head := label(title, 15, ACCENT)
	box.add_child(head)
	return {"panel": panel, "body": box}


static func field_row(label_text: String, control: Control, label_width: int = 84) -> HBoxContainer:
	var row := hbox(8)
	var l := label(label_text, 13, MUTED)
	l.custom_minimum_size.x = label_width
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


static func separator() -> HSeparator:
	var s := HSeparator.new()
	s.add_theme_constant_override("separation", 6)
	return s


static func margin(child: Control, left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", left)
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_right", right)
	m.add_theme_constant_override("margin_bottom", bottom)
	m.add_child(child)
	return m


static func set_full_rect(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


static func monospace_font() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Cascadia Mono", "Consolas", "Menlo", "DejaVu Sans Mono", "monospace"])
	return font
