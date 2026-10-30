class_name FxRipple
extends Control
## 按钮点击波纹。只保留一个 Tween，连续点击会重置而不是叠加。

var _color := Color(0.53, 0.81, 0.92, 0.35)
var _origin := Vector2.ZERO
var _radius := 0.0
var _max_radius := 40.0
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func pulse(position: Vector2, color: Color) -> void:
	_color = color
	_origin = position
	_max_radius = maxf(size.x, size.y) * 0.9
	_radius = 0.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_radius, 0.0, _max_radius, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(func() -> void:
		_radius = 0.0
		queue_redraw()
	)


func _set_radius(value: float) -> void:
	_radius = value
	queue_redraw()


func _draw() -> void:
	if _radius <= 0.1:
		return
	var alpha := clampf(1.0 - _radius / maxf(_max_radius, 1.0), 0.0, 1.0)
	draw_circle(_origin, _radius, Color(_color.r, _color.g, _color.b, _color.a * alpha))
