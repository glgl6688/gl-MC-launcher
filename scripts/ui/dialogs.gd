class_name LauncherDialogs
extends Node
## 全局对话框：统一错误框、结果报告、文件/目录选择、整合包目标选择。

signal files_picked(role: String, paths: PackedStringArray)
signal dir_picked(role: String, path: String)
signal mrpack_target_confirmed(instance_dir: String, source_dir: String)
signal confirm_accepted(action: String)
signal components_confirmed(paths: PackedStringArray)

const UiKitScript = preload("res://scripts/ui/ui_kit.gd")
const FileUtilsScript = preload("res://scripts/core/file_utils.gd")

var _built := false
var _error_dialog: AcceptDialog
var _error_title: Label
var _error_body: RichTextLabel
var _error_path_row: HBoxContainer
var _error_path: LineEdit
var _error_open_btn: Button
var _error_copy_btn: Button
var _error_current: Dictionary = {}

var _report_dialog: AcceptDialog
var _report_title: Label
var _report_body: RichTextLabel
var _report_copy_text := ""

var _file_dialog: FileDialog
var _file_role := ""
var _dir_dialog: FileDialog
var _dir_role := ""

var _mrpack_dialog: ConfirmationDialog
var _mrpack_list: ItemList
var _mrpack_source: LineEdit
var _mrpack_note: Label
var _mrpack_dirs: Array[String] = []
var _source_dir_dialog: FileDialog
var _confirm_dialog: ConfirmationDialog
var _confirm_action := ""
var _components_dialog: ConfirmationDialog
var _components_box: VBoxContainer
var _components_checks: Array[CheckBox] = []


func _ready() -> void:
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	_build_error_dialog()
	_build_report_dialog()
	_build_file_dialogs()
	_build_mrpack_dialog()
	_build_confirm_dialog()
	_build_components_dialog()


func _build_confirm_dialog() -> void:
	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "请确认"
	_confirm_dialog.min_size = Vector2i(520, 180)
	_confirm_dialog.get_ok_button().text = "确认"
	_confirm_dialog.get_ok_button().add_theme_color_override("font_color", UiKitScript.ERROR)
	_confirm_dialog.get_cancel_button().text = "取消"
	_confirm_dialog.confirmed.connect(_on_confirm_pressed)
	add_child(_confirm_dialog)


func confirm_action(action: String, title: String, text: String) -> void:
	if _confirm_dialog == null:
		return
	_confirm_action = action
	_confirm_dialog.title = title
	_confirm_dialog.dialog_text = text
	_confirm_dialog.popup_centered(Vector2i(560, 220))


func _on_confirm_pressed() -> void:
	var action := _confirm_action
	_confirm_action = ""
	confirm_accepted.emit(action)


func _build_components_dialog() -> void:
	_components_dialog = ConfirmationDialog.new()
	_components_dialog.title = "管理组件"
	_components_dialog.min_size = Vector2i(620, 480)
	_components_dialog.get_ok_button().text = "移出所选"
	_components_dialog.get_ok_button().add_theme_color_override("font_color", UiKitScript.WARN)
	_components_dialog.get_cancel_button().text = "取消"
	_components_dialog.confirmed.connect(_on_components_confirmed)
	add_child(_components_dialog)
	var box := UiKitScript.vbox(8)
	_components_dialog.add_child(box)
	box.add_child(UiKitScript.wrapped_label(
		"选中的组件会移动到 .minecraft 外面的 gl-component-backup 备份目录，不会直接删除。",
		12, UiKitScript.WARN))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(580, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_components_box = UiKitScript.vbox(4)
	_components_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_components_box)


func show_components(info: Dictionary) -> void:
	if _components_dialog == null:
		return
	for child in _components_box.get_children():
		child.queue_free()
	_components_checks.clear()
	var last_category := ""
	for item in info.get("items", []):
		if not (item is Dictionary):
			continue
		var category := str(item.get("category", ""))
		if category != last_category:
			last_category = category
			_components_box.add_child(UiKitScript.label(str(item.get("label", category)), 14, UiKitScript.ACCENT))
		var check := CheckBox.new()
		check.text = str(item.get("name", ""))
		check.set_meta("path", str(item.get("path", "")))
		check.tooltip_text = str(item.get("path", ""))
		_components_box.add_child(check)
		_components_checks.append(check)
	_components_dialog.popup_centered(Vector2i(640, 520))


func _on_components_confirmed() -> void:
	var paths := PackedStringArray()
	for check in _components_checks:
		if check.button_pressed:
			paths.append(str(check.get_meta("path", "")))
	if not paths.is_empty():
		components_confirmed.emit(paths)


func _build_error_dialog() -> void:
	_error_dialog = AcceptDialog.new()
	_error_dialog.title = "启动器错误"
	_error_dialog.min_size = Vector2i(700, 360)
	_error_dialog.get_ok_button().text = "知道了"
	var box := UiKitScript.vbox(10)
	_error_dialog.add_child(box)
	_error_title = UiKitScript.label("错误", 18, UiKitScript.ERROR)
	box.add_child(_error_title)
	_error_body = RichTextLabel.new()
	_error_body.bbcode_enabled = true
	_error_body.fit_content = false
	_error_body.selection_enabled = true
	_error_body.custom_minimum_size = Vector2(660, 170)
	_error_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_error_body)
	_error_path_row = HBoxContainer.new()
	_error_path_row.add_theme_constant_override("separation", 8)
	_error_path = LineEdit.new()
	_error_path.editable = false
	_error_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_error_path.add_theme_font_size_override("font_size", 12)
	_error_path_row.add_child(_error_path)
	_error_copy_btn = UiKitScript.button("复制路径")
	_error_copy_btn.pressed.connect(_copy_error_path)
	_error_path_row.add_child(_error_copy_btn)
	_error_open_btn = UiKitScript.button("打开所在目录")
	_error_open_btn.pressed.connect(_open_error_path)
	_error_path_row.add_child(_error_open_btn)
	box.add_child(_error_path_row)
	_error_dialog.add_button("复制详情", true, "copy_details")
	_error_dialog.custom_action.connect(_on_error_custom_action)
	_error_dialog.confirmed.connect(func() -> void:
		if is_instance_valid(_error_copy_btn):
			_error_copy_btn.text = "复制路径"
	)
	add_child(_error_dialog)


func _build_report_dialog() -> void:
	_report_dialog = AcceptDialog.new()
	_report_dialog.title = "操作结果"
	_report_dialog.min_size = Vector2i(660, 380)
	_report_dialog.get_ok_button().text = "关闭"
	var box := UiKitScript.vbox(10)
	_report_dialog.add_child(box)
	_report_title = UiKitScript.label("结果", 18, UiKitScript.ACCENT)
	box.add_child(_report_title)
	_report_body = RichTextLabel.new()
	_report_body.bbcode_enabled = false
	_report_body.fit_content = false
	_report_body.selection_enabled = true
	_report_body.custom_minimum_size = Vector2(620, 240)
	_report_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_report_body)
	_report_dialog.add_button("复制内容", true, "copy_report")
	_report_dialog.custom_action.connect(func(action: StringName) -> void:
		if action == &"copy_report":
			_copy_text(_report_copy_text, "报告内容")
	)
	add_child(_report_dialog)


func _build_file_dialogs() -> void:
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.file_selected.connect(_on_file_selected)
	_file_dialog.files_selected.connect(_on_files_selected)
	add_child(_file_dialog)

	_dir_dialog = FileDialog.new()
	_dir_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dir_dialog.use_native_dialog = true
	_dir_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_dir_dialog.dir_selected.connect(_on_dir_selected)
	add_child(_dir_dialog)


func _build_mrpack_dialog() -> void:
	_mrpack_dialog = ConfirmationDialog.new()
	_mrpack_dialog.title = "选择整合包导入目标"
	_mrpack_dialog.min_size = Vector2i(620, 470)
	_mrpack_dialog.get_ok_button().text = "开始导入"
	_mrpack_dialog.get_cancel_button().text = "取消"
	var box := UiKitScript.vbox(10)
	_mrpack_dialog.add_child(box)
	_mrpack_note = UiKitScript.wrapped_label("", 13, UiKitScript.MUTED)
	_mrpack_note.custom_minimum_size.x = 620
	box.add_child(_mrpack_note)
	box.add_child(UiKitScript.label("目标实例", 14, UiKitScript.ACCENT))
	_mrpack_list = ItemList.new()
	_mrpack_list.custom_minimum_size.y = 200
	_mrpack_list.size_flags_vertical = Control.SIZE_FILL
	box.add_child(_mrpack_list)
	box.add_child(UiKitScript.label("本地资源来源目录（可选）", 13, UiKitScript.MUTED))
	var src_row := HBoxContainer.new()
	src_row.add_theme_constant_override("separation", 8)
	_mrpack_source = LineEdit.new()
	_mrpack_source.placeholder_text = "若整合包的 files 已在本地缓存，可在此选择缓存根目录"
	_mrpack_source.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	src_row.add_child(_mrpack_source)
	var browse := UiKitScript.button("浏览…")
	browse.pressed.connect(_browse_mrpack_source)
	src_row.add_child(browse)
	box.add_child(src_row)
	var hint := UiKitScript.wrapped_label("只复制整合包内 overrides 与来源目录中已存在的文件；缺失项不会联网下载，会在结果中列出。", 12, UiKitScript.MUTED)
	hint.custom_minimum_size.x = 620
	box.add_child(hint)
	_mrpack_dialog.confirmed.connect(_on_mrpack_confirmed)
	add_child(_mrpack_dialog)

	_source_dir_dialog = FileDialog.new()
	_source_dir_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_source_dir_dialog.use_native_dialog = true
	_source_dir_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_source_dir_dialog.title = "选择本地资源来源目录"
	_source_dir_dialog.dir_selected.connect(func(path: String) -> void:
		_mrpack_source.text = FileUtilsScript.normalize(path)
	)
	_mrpack_dialog.add_child(_source_dir_dialog)


func show_error(err: Dictionary) -> void:
	_build()
	# 同一时间只保留一个模态子窗口，避免与其他结果框/选择框冲突。
	if _report_dialog.visible:
		_report_dialog.hide()
	if _mrpack_dialog.visible:
		_mrpack_dialog.hide()
	if _file_dialog.visible:
		_file_dialog.hide()
	if _dir_dialog.visible:
		_dir_dialog.hide()
	if _source_dir_dialog.visible:
		_source_dir_dialog.hide()
	_error_current = err
	_error_title.text = str(err.get("title", "启动器错误"))
	var message := str(err.get("message", ""))
	var hint := str(err.get("fix_hint", ""))
	var body := "[b]原因[/b]\n" + _bb(message)
	if not hint.is_empty():
		body += "\n\n[b]修复建议[/b]\n" + _bb(hint)
	_error_body.text = body
	var path := str(err.get("path", "")).strip_edges()
	if path.begins_with("user://") or path.begins_with("res://"):
		path = ProjectSettings.globalize_path(path).replace("\\", "/")
	_error_path.text = path
	_error_path.tooltip_text = path
	_error_path_row.visible = not path.is_empty()
	_error_open_btn.disabled = _nearest_existing_dir(path).is_empty()
	_error_copy_btn.text = "复制路径"
	if _error_dialog.visible:
		_error_dialog.move_to_foreground()
	else:
		_error_dialog.popup_centered(Vector2i(720, 420))


func show_report(title: String, text: String, copy_text: String = "") -> void:
	_build()
	if _error_dialog.visible:
		_error_dialog.hide()
	_report_title.text = title
	_report_body.text = text
	_report_copy_text = copy_text if not copy_text.is_empty() else text
	if _report_dialog.visible:
		_report_dialog.move_to_foreground()
	else:
		_report_dialog.popup_centered(Vector2i(680, 460))


func pick_files(role: String, title: String, filters: PackedStringArray, multiple: bool = true, start_dir: String = "") -> void:
	_build()
	_file_role = role
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES if multiple else FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.filters = filters
	_file_dialog.title = title
	if not start_dir.is_empty() and DirAccess.dir_exists_absolute(start_dir):
		_file_dialog.current_dir = start_dir
	_file_dialog.popup_centered_ratio(0.72)


func pick_dir(role: String, title: String, start_dir: String = "") -> void:
	_build()
	_dir_role = role
	_dir_dialog.title = title
	if not start_dir.is_empty() and DirAccess.dir_exists_absolute(start_dir):
		_dir_dialog.current_dir = start_dir
	_dir_dialog.popup_centered_ratio(0.72)


func show_mrpack_target(instances: Array, pack_name: String, current_version: String) -> void:
	_build()
	_mrpack_list.clear()
	_mrpack_dirs.clear()
	var selected_index := -1
	for i in range(instances.size()):
		var item: Dictionary = instances[i]
		var version_id := str(item.get("version_id", ""))
		var last := str(item.get("last_launch", ""))
		var text := "%s   ·   版本 %s" % [str(item.get("name", "")), version_id]
		if not last.is_empty():
			text += "   ·   最近启动 " + last.replace("T", " ")
		var idx := _mrpack_list.add_item(text)
		_mrpack_dirs.append(str(item.get("dir", "")))
		if selected_index < 0 and version_id == current_version:
			selected_index = idx
	if selected_index >= 0:
		_mrpack_list.select(selected_index)
	elif instances.size() > 0:
		_mrpack_list.select(0)
	_mrpack_source.text = ""
	_mrpack_note.text = "整合包：%s\n请选择要导入的实例。导入只使用本地文件，不会联网下载。" % pack_name
	_mrpack_dialog.get_ok_button().disabled = instances.is_empty()
	_mrpack_dialog.popup_centered(Vector2i(680, 520))


func _on_mrpack_confirmed() -> void:
	var selected := _mrpack_list.get_selected_items()
	if selected.is_empty():
		LogManager.warn("没有选择整合包目标实例")
		return
	var idx := int(selected[0])
	if idx < 0 or idx >= _mrpack_dirs.size():
		return
	mrpack_target_confirmed.emit(_mrpack_dirs[idx], FileUtilsScript.normalize(_mrpack_source.text))


func _browse_mrpack_source() -> void:
	_source_dir_dialog.popup_centered_ratio(0.7)


func _on_file_selected(path: String) -> void:
	var normalized := FileUtilsScript.normalize(path)
	files_picked.emit(_file_role, PackedStringArray([normalized]))


func _on_files_selected(paths: PackedStringArray) -> void:
	var out := PackedStringArray()
	for p in paths:
		out.append(FileUtilsScript.normalize(p))
	files_picked.emit(_file_role, out)


func _on_dir_selected(path: String) -> void:
	dir_picked.emit(_dir_role, FileUtilsScript.normalize(path))


func _copy_error_path() -> void:
	_copy_text(_error_path.text, "路径")
	_error_copy_btn.text = "已复制"
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
		if is_instance_valid(_error_copy_btn):
			_error_copy_btn.text = "复制路径"
	)


func _on_error_custom_action(action: StringName) -> void:
	if action != &"copy_details":
		return
	var details := str(_error_current.get("title", "")) + "\n" + str(_error_current.get("message", ""))
	var path := str(_error_current.get("path", ""))
	if not path.is_empty():
		details += "\n路径：" + path
	var hint := str(_error_current.get("fix_hint", ""))
	if not hint.is_empty():
		details += "\n修复建议：" + hint
	_copy_text(details, "错误详情")


func _open_error_path() -> void:
	var raw := str(_error_current.get("path", ""))
	if raw.begins_with("user://") or raw.begins_with("res://"):
		raw = ProjectSettings.globalize_path(raw).replace("\\", "/")
	var dir := _nearest_existing_dir(raw)
	if dir.is_empty():
		LogManager.warn("没有可打开的目录")
		return
	var err := OS.shell_open(dir)
	if err != OK:
		LogManager.warn("无法打开目录：%s（%s）" % [dir, error_string(err)])


func _nearest_existing_dir(path: String) -> String:
	var p := FileUtilsScript.normalize(path)
	if p.is_empty():
		return ""
	if DirAccess.dir_exists_absolute(p):
		return p
	var dir := p.get_base_dir()
	var guard := 0
	while not dir.is_empty() and guard < 20:
		if DirAccess.dir_exists_absolute(dir):
			return dir
		var parent := dir.get_base_dir()
		if parent == dir:
			break
		dir = parent
		guard += 1
	return ""


func _copy_text(text: String, label: String) -> void:
	if text.is_empty():
		return
	DisplayServer.clipboard_set(text)
	LogManager.info("已复制%s到剪贴板" % label)


func _bb(text: String) -> String:
	return text.replace("[", "[lb]")
