class_name VersionPanel
extends VBoxContainer
## 左侧版本树：每个游戏文件夹是父节点，版本文件夹是子节点，可折叠。

signal refresh_requested
signal version_chosen(entry: Dictionary)
signal version_activated(entry: Dictionary)
signal root_selected(root: String)

const UiKitScript = preload("res://scripts/ui/ui_kit.gd")

var _tree: Tree
var _count: Label
var _refresh: Button
var _empty_box: VBoxContainer
var _empty_label: Label
var _empty_path: LineEdit
var _copy_btn: Button
var _reason: Label
var _reason_row: HBoxContainer
var _reason_copy: Button
var _root_path_row: HBoxContainer
var _root_path: LineEdit
var _root_copy: Button
var _entries: Array[Dictionary] = []
var _version_items := {}
var _root_items := {}
var _selected_entry: Dictionary = {}
var _built := false


func build() -> void:
	if _built:
		return
	_built = true
	add_theme_constant_override("separation", 10)
	custom_minimum_size.x = 410

	var head := UiKitScript.hbox(8)
	head.add_child(UiKitScript.label("游戏版本", 17, UiKitScript.ACCENT))
	head.add_child(UiKitScript.spacer(true))
	_count = UiKitScript.label("", 12, UiKitScript.MUTED)
	head.add_child(_count)
	add_child(head)

	_refresh = UiKitScript.button("重新扫描")
	_refresh.pressed.connect(func() -> void: refresh_requested.emit())
	add_child(_refresh)

	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.columns = 5
	_tree.column_titles_visible = true
	_tree.set_column_title(0, "版本文件夹")
	_tree.set_column_title(1, "Mod")
	_tree.set_column_title(2, "光影")
	_tree.set_column_title(3, "材质")
	_tree.set_column_title(4, "存档")
	_tree.set_column_expand(0, true)
	_tree.select_mode = Tree.SELECT_ROW
	_tree.item_selected.connect(_on_item_selected)
	_tree.item_activated.connect(_on_item_activated)
	add_child(_tree)

	_root_path_row = UiKitScript.hbox(6)
	_root_path_row.add_child(UiKitScript.label("根文件夹", 12, UiKitScript.MUTED))
	_root_path = LineEdit.new()
	_root_path.editable = false
	_root_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root_path.add_theme_font_size_override("font_size", 12)
	_root_path_row.add_child(_root_path)
	_root_copy = UiKitScript.button("复制")
	_root_copy.custom_minimum_size.x = 56
	_root_copy.pressed.connect(_copy_root_path)
	_root_path_row.add_child(_root_copy)
	_root_path_row.visible = false
	add_child(_root_path_row)

	_reason_row = UiKitScript.hbox(6)
	_reason = UiKitScript.wrapped_label("", 12, UiKitScript.WARN)
	_reason_row.add_child(_reason)
	_reason_copy = UiKitScript.button("复制路径")
	_reason_copy.custom_minimum_size.x = 72
	_reason_copy.pressed.connect(_copy_reason_path)
	_reason_row.add_child(_reason_copy)
	_reason_row.visible = false
	add_child(_reason_row)

	_empty_box = UiKitScript.vbox(8)
	_empty_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty_label = UiKitScript.wrapped_label("", 13, UiKitScript.MUTED)
	_empty_box.add_child(_empty_label)
	var path_row := UiKitScript.hbox(6)
	_empty_path = LineEdit.new()
	_empty_path.editable = false
	_empty_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_empty_path.add_theme_font_size_override("font_size", 12)
	path_row.add_child(_empty_path)
	_copy_btn = UiKitScript.button("复制")
	_copy_btn.custom_minimum_size.x = 56
	_copy_btn.pressed.connect(_copy_empty_path)
	path_row.add_child(_copy_btn)
	_empty_box.add_child(path_row)
	_empty_box.visible = false
	add_child(_empty_box)


func show_loading() -> void:
	_count.text = "扫描中…"
	_refresh.disabled = true


func set_scan_result(result: Dictionary) -> void:
	_refresh.disabled = false
	_entries.clear()
	_version_items.clear()
	_root_items.clear()
	_tree.clear()
	_root_path_row.visible = false
	_root_path.text = ""
	if _tree.get_root() == null:
		_tree.create_item()
	_reason_row.visible = false
	_selected_entry = {}

	if not bool(result.get("ok", false)):
		var err: Dictionary = result.get("error", {})
		_show_empty("无法读取版本目录。\n" + str(err.get("message", "")), str(err.get("path", "")))
		_count.text = "读取失败"
		return

	var roots: Array = result.get("roots", [])
	var versions: Array = result.get("versions", [])
	for root in roots:
		var root_path := str(root)
		var item := _tree.create_item(_tree.get_root())
		item.set_text(0, root_path.get_file() if not root_path.get_file().is_empty() else root_path)
		item.set_tooltip_text(0, root_path)
		item.set_metadata(0, {"kind": "root", "root": root_path})
		item.set_collapsed(false)
		_root_items[root_path] = item

	for v in versions:
		if not (v is Dictionary):
			continue
		var entry: Dictionary = v
		_entries.append(entry)
		var root_path := str(entry.get("root", ""))
		var parent: TreeItem = _root_items.get(root_path, null)
		if parent == null:
			parent = _tree.create_item(_tree.get_root())
			parent.set_text(0, root_path.get_file() if not root_path.get_file().is_empty() else root_path)
			parent.set_tooltip_text(0, root_path)
			parent.set_metadata(0, {"kind": "root", "root": root_path})
			parent.set_collapsed(false)
			_root_items[root_path] = parent
		var id := str(entry.get("id", ""))
		var child := _tree.create_item(parent)
		# 版本名严格使用版本文件夹的名字，不采用 JSON 里的 name/id。
		child.set_text(0, id)
		child.set_text(1, str(int(entry.get("mod_count", 0))))
		child.set_text(2, str(int(entry.get("shader_count", 0))))
		child.set_text(3, str(int(entry.get("resourcepack_count", 0))))
		child.set_text(4, str(int(entry.get("save_count", 0))))
		child.set_metadata(0, entry)
		_version_items[root_path + "|" + id] = child
		if bool(entry.get("usable", false)):
			child.set_custom_color(0, UiKitScript.TEXT)
			child.set_tooltip_text(0, str(entry.get("dir", "")))
		else:
			child.set_custom_color(0, UiKitScript.MUTED)
			child.set_tooltip_text(0, str(entry.get("reason", "")) + "\n\n" + str(entry.get("fix_hint", "")))

	if _root_items.is_empty():
		_show_empty("尚未添加游戏文件夹。\n点击顶部「添加游戏文件夹」，选择包含 versions 的目录。", "")
		_count.text = "0 个文件夹"
		return

	_hide_empty()
	if _entries.is_empty():
		var paths: Array[String] = []
		for root in roots:
			paths.append(str(root))
		_show_empty("这些文件夹里没有发现版本。\n请确认 versions/<版本id>/<版本id>.json 与 .jar 存在，然后重新扫描。", "\n".join(paths))
		_count.text = "%d 个文件夹 · 0 个版本" % roots.size()
		return

	var usable := 0
	for entry in _entries:
		if bool(entry.get("usable", false)):
			usable += 1
	_count.text = "%d 个文件夹 · %d 个版本 · 可用 %d" % [roots.size(), _entries.size(), usable]


func select_version(version_id: String, root: String = "") -> void:
	var found: TreeItem = null
	if not root.is_empty():
		found = _version_items.get(root + "|" + version_id, null)
	else:
		for key in _version_items.keys():
			if str(key).ends_with("|" + version_id):
				found = _version_items[key]
				break
	if found == null:
		return
	found.select(0)
	if found.get_metadata(0) is Dictionary:
		_choose(found.get_metadata(0))


func current_entry() -> Dictionary:
	return _selected_entry


func selected_root() -> String:
	var item := _tree.get_selected()
	if item == null:
		return ""
	var meta: Variant = item.get_metadata(0)
	if meta is Dictionary:
		return str(meta.get("root", ""))
	return ""


func _show_empty(message: String, path: String) -> void:
	_tree.visible = false
	_root_path_row.visible = false
	_empty_box.visible = true
	_empty_label.text = message
	_empty_path.text = path
	_empty_path.tooltip_text = path
	_empty_path.caret_column = 0


func _hide_empty() -> void:
	_tree.visible = true
	_empty_box.visible = false


func _copy_empty_path() -> void:
	var path := _empty_path.text
	if path.is_empty():
		return
	DisplayServer.clipboard_set(path)
	LogManager.info("已复制路径到剪贴板：" + path)
	_copy_btn.text = "已复制"
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
		if is_instance_valid(_copy_btn):
			_copy_btn.text = "复制"
	)


func _copy_root_path() -> void:
	if _root_path.text.is_empty():
		return
	DisplayServer.clipboard_set(_root_path.text)
	LogManager.info("已复制游戏文件夹路径到剪贴板：" + _root_path.text)
	_root_copy.text = "已复制"
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
		if is_instance_valid(_root_copy):
			_root_copy.text = "复制"
	)


func _copy_reason_path() -> void:
	if _selected_entry.is_empty():
		return
	var path := str(_selected_entry.get("dir", ""))
	if path.is_empty():
		return
	DisplayServer.clipboard_set(path)
	LogManager.info("已复制版本目录到剪贴板：" + path)
	_reason_copy.text = "已复制"
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
		if is_instance_valid(_reason_copy):
			_reason_copy.text = "复制路径"
	)


func _on_item_selected() -> void:
	var item := _tree.get_selected()
	if item == null:
		return
	var meta: Variant = item.get_metadata(0)
	if not (meta is Dictionary):
		return
	if str(meta.get("kind", "")) == "root":
		_reason_row.visible = false
		_root_path.text = str(meta.get("root", ""))
		_root_path.tooltip_text = _root_path.text
		_root_path.caret_column = 0
		_root_path_row.visible = true
		root_selected.emit(str(meta.get("root", "")))
		return
	_choose(meta)


func _on_item_activated() -> void:
	var item := _tree.get_selected()
	if item == null:
		return
	var meta: Variant = item.get_metadata(0)
	if meta is Dictionary and not meta.has("kind"):
		version_activated.emit(meta)


func _choose(entry: Dictionary) -> void:
	_selected_entry = entry
	_root_path_row.visible = false
	if bool(entry.get("usable", false)):
		_reason_row.visible = false
	else:
		_reason.text = "不可用：" + str(entry.get("reason", "")) + "\n建议：" + str(entry.get("fix_hint", ""))
		_reason_row.visible = true
	version_chosen.emit(entry)
