class_name FxButton
extends Button
## 统一按钮动效：悬停亮度、底部光条、按下缩放、点击波纹、焦点、成功/失败反馈。
## 动效时长都 <= 0.35s；减少动效时只保留极短透明度变化。

const ACCENT := Color("#87ceeb")
const SUCCESS := Color("#65e0a3")
const ERROR := Color("#ef7b7b")
const FxRippleScript = preload("res://scripts/ui/fx_ripple.gd")

var is_primary := false
var show_progress := false
var progress := 0.0

var _hover_tween: Tween
var _press_tween: Tween
var _feedback_tween: Tween
var _underline_tween: Tween
var _underline: ColorRect
var _ripple: Control
var _hovering := false
var _last_disabled := false


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	pivot_offset = size * 0.5
	_underline = ColorRect.new()
	_underline.color = SUCCESS if is_primary else ACCENT
	_underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_underline.size = Vector2(0, 2)
	add_child(_underline)
	_ripple = FxRippleScript.new()
	add_child(_ripple)
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_on_unhover)
	button_down.connect(_on_down)
	button_up.connect(_on_up)
	focus_entered.connect(_on_focus)
	focus_exited.connect(_on_unfocus)
	resized.connect(_layout_fx)
	_layout_fx()
	set_process(true)


func _process(_delta: float) -> void:
	if disabled != _last_disabled:
		_last_disabled = disabled
		self_modulate.a = 0.5 if disabled else 1.0
		mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if disabled else Control.CURSOR_POINTING_HAND
		if disabled:
			_on_unhover()


func _layout_fx() -> void:
	pivot_offset = size * 0.5
	if _underline == null:
		return
	_underline.position = Vector2(0, maxf(0, size.y - 2))
	_underline.size = Vector2(0 if not _hovering else size.x, 2)
	_ripple.size = size
	queue_redraw()


func _motion(base: float) -> float:
	return 0.0 if bool(ConfigManager.reduce_motion) else base


func _tween_to_modulate(target: Color, duration: float) -> void:
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "self_modulate", target, _motion(duration)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_hover() -> void:
	if disabled:
		return
	_hovering = true
	if not bool(ConfigManager.reduce_motion):
		_tween_to_modulate(Color(1.08, 1.08, 1.08, 1.0), 0.08)
		if _underline != null:
			if _underline_tween != null and _underline_tween.is_valid():
				_underline_tween.kill()
			_underline_tween = create_tween()
			_underline_tween.tween_property(_underline, "size:x", size.x, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_unhover() -> void:
	_hovering = false
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "self_modulate", Color(1, 1, 1, 0.5 if disabled else 1.0), _motion(0.08))
	if _underline != null:
		if _underline_tween != null and _underline_tween.is_valid():
			_underline_tween.kill()
		_underline_tween = create_tween()
		_underline_tween.tween_property(_underline, "size:x", 0.0, _motion(0.12))


func _on_down() -> void:
	if disabled:
		return
	_pivot_center()
	if _ripple != null:
		var local := get_local_mouse_position()
		_ripple.pulse(local, SUCCESS if is_primary else ACCENT)
	if bool(ConfigManager.reduce_motion):
		return
	if _press_tween != null and _press_tween.is_valid():
		_press_tween.kill()
	_press_tween = create_tween()
	_press_tween.tween_property(self, "scale", Vector2(0.95, 0.95), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_press_tween.tween_property(self, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_up() -> void:
	_pivot_center()
	if _press_tween != null and _press_tween.is_valid():
		_press_tween.kill()
	_press_tween = create_tween()
	_press_tween.tween_property(self, "scale", Vector2.ONE, _motion(0.12)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_focus() -> void:
	if _underline == null or disabled:
		return
	_underline.color = SUCCESS if is_primary else ACCENT
	_underline.size.x = size.x


func _on_unfocus() -> void:
	if _underline == null:
		return
	_underline.size.x = size.x if _hovering else 0.0


func _pivot_center() -> void:
	pivot_offset = size * 0.5


func play_success() -> void:
	if _feedback_tween != null and _feedback_tween.is_valid():
		_feedback_tween.kill()
	_feedback_tween = create_tween()
	_feedback_tween.tween_property(self, "self_modulate", Color(1.0, 1.25, 1.15, 1.0), 0.08)
	_feedback_tween.tween_property(self, "self_modulate", Color.WHITE, 0.22)


func set_launch_progress(value: float, visible: bool = true) -> void:
	progress = clampf(value, 0.0, 1.0)
	show_progress = visible
	queue_redraw()


func play_failure() -> void:
	if _feedback_tween != null and _feedback_tween.is_valid():
		_feedback_tween.kill()
	_feedback_tween = create_tween()
	for i in range(3):
		_feedback_tween.tween_property(self, "self_modulate", Color(1.35, 0.8, 0.8, 1.0), 0.06)
		_feedback_tween.tween_property(self, "self_modulate", Color.WHITE, 0.06)


func _draw() -> void:
	if not show_progress:
		return
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 2.0
	if radius <= 1.0:
		return
	var start := -PI * 0.5
	var end := start + TAU * clampf(progress, 0.0, 1.0)
	var color := SUCCESS if progress >= 0.999 else ACCENT
	draw_arc(center, radius, start, end, 48, color, 2.0, true)
