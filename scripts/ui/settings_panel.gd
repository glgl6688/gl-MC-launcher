class_name SettingsPanel
extends VBoxContainer
## 右侧版本设置区：启动模式、Java、实例、资源导入与底部操作栏。
## 只负责收集输入与展示状态，实际保存/启动由 main.gd 协调。

signal save_requested
signal launch_requested
signal manual_java_requested
signal java_mode_changed
signal java_help_requested
signal open_instance_requested
signal manage_components_requested
signal import_mrpack_requested
signal install_mod_requested
signal install_shader_requested
signal install_resource_requested
signal thirdparty_login_requested
signal authlib_pick_requested
signal premium_login_requested
signal changed

const UiKitScript = preload("res://scripts/ui/ui_kit.gd")
const FileUtilsScript = preload("res://scripts/core/file_utils.gd")
const InstanceConfigScript = preload("res://scripts/core/instance_config.gd")

var _version_label: Label
var _account_mode: OptionButton
var _username: LineEdit
var _auth_url: LineEdit
var _account_note: Label
var _auth_row: HBoxContainer
var _password_row: HBoxContainer
var _password: LineEdit
var _login_row: HBoxContainer
var _login_btn: Button
var _login_status: Label
var _authlib_row: HBoxContainer
var _authlib_path: LineEdit
var _authlib_btn: Button
var _ms_login_row: HBoxContainer
var _ms_login_btn: Button
var _ms_status: Label
var _ms_code_row: HBoxContainer
var _ms_code: LineEdit
var _ms_copy_btn: Button
var _ms_open_btn: Button
var _ms_verify_uri := ""
var _ms_busy := false
var _java_auto: CheckBox
var _java_manual_btn: Button
var _java_path: LineEdit
var _java_status: Label
var _java_help: Button
var _memory: SpinBox
var _auto_chinese: CheckBox
var _reduce_motion: CheckBox
var _low_spec: CheckBox
var _component_summary: Label
var _instance_hint: Label
var _open_instance_btn: Button
var _manage_components_btn: Button
var _resource_buttons: Array[Button] = []
var _launch_btn: Button
var _save_btn: Button
var _progress: ProgressBar
var _status: Label

var _enabled := false
var _busy := false
var _running := false
var _login_busy := false
var _built := false
var _suppress := false
var _last_java_result: Dictionary = {}
var _current_version_id := ""


func build() -> void:
	if _built:
		return
	_built = true
	add_theme_constant_override("separation", 10)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var content := UiKitScript.vbox(10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

	var head := UiKitScript.hbox(10)
	head.add_child(UiKitScript.label("版本设置", 18, UiKitScript.ACCENT))
	_version_label = UiKitScript.label("尚未选择版本", 13, UiKitScript.MUTED)
	_version_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_version_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_version_label)
	content.add_child(head)

	content.add_child(_build_account_card())
	content.add_child(_build_java_card())
	content.add_child(_build_instance_card())
	content.add_child(_build_resource_card())
	content.add_child(_build_fx_card())

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 4
	content.add_child(spacer)

	add_child(UiKitScript.separator())
	add_child(_build_action_bar())
	_refresh_controls()
	_on_account_mode_changed(_account_mode.selected)
	set_status("请选择一个可用版本", "info")


func _build_account_card() -> PanelContainer:
	var card := UiKitScript.card(10)
	var body := UiKitScript.vbox(8)
	card.add_child(body)
	body.add_child(UiKitScript.label("启动模式", 15, UiKitScript.ACCENT))

	_account_mode = OptionButton.new()
	_account_mode.add_item("正版（Microsoft 登录）", 0)
	_account_mode.add_item("离线", 1)
	_account_mode.add_item("第三方认证（Yggdrasil）", 2)
	_account_mode.item_selected.connect(_on_account_mode_changed)
	body.add_child(UiKitScript.field_row("模式", _account_mode, 72))

	_username = LineEdit.new()
	_username.placeholder_text = "第三方邮箱/用户名，或离线玩家名"
	_username.max_length = 64
	_username.text_changed.connect(func(_text: String) -> void: _emit_changed())
	body.add_child(UiKitScript.field_row("邮箱/用户名", _username, 88))

	_ms_login_row = UiKitScript.hbox(8)
	_ms_login_btn = UiKitScript.button("登录正版")
	_ms_login_btn.pressed.connect(func() -> void: premium_login_requested.emit())
	_ms_login_row.add_child(_ms_login_btn)
	_ms_status = UiKitScript.label("未登录", 12, UiKitScript.MUTED)
	_ms_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ms_login_row.add_child(_ms_status)
	body.add_child(_ms_login_row)

	_ms_code_row = UiKitScript.hbox(6)
	_ms_code = LineEdit.new()
	_ms_code.editable = false
	_ms_code.placeholder_text = "验证码会显示在这里"
	_ms_code.add_theme_font_size_override("font_size", 17)
	_ms_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ms_code_row.add_child(_ms_code)
	_ms_copy_btn = UiKitScript.button("复制验证码")
	_ms_copy_btn.pressed.connect(_copy_ms_code)
	_ms_code_row.add_child(_ms_copy_btn)
	_ms_open_btn = UiKitScript.button("打开登录页")
	_ms_open_btn.pressed.connect(_open_ms_browser)
	_ms_code_row.add_child(_ms_open_btn)
	_ms_code_row.visible = false
	body.add_child(_ms_code_row)

	_auth_url = LineEdit.new()
	_auth_url.placeholder_text = "Yggdrasil 根地址，例如 https://littleskin.cn/api/yggdrasil"
	_auth_url.text_changed.connect(func(_text: String) -> void: _emit_changed())
	var auth_box := UiKitScript.hbox(6)
	_auth_url.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auth_box.add_child(_auth_url)
	var auth_site_btn := UiKitScript.button("打开网站")
	auth_site_btn.pressed.connect(_open_auth_site)
	auth_box.add_child(auth_site_btn)
	_auth_row = UiKitScript.field_row("认证地址", auth_box, 72)
	body.add_child(_auth_row)

	_password = LineEdit.new()
	_password.secret = true
	_password.placeholder_text = "第三方账号密码（只发送到上方地址，不保存）"
	_password_row = UiKitScript.field_row("密码", _password, 72)
	body.add_child(_password_row)

	_login_row = UiKitScript.hbox(8)
	_login_btn = UiKitScript.button("登录第三方")
	_login_btn.pressed.connect(func() -> void: thirdparty_login_requested.emit())
	_login_row.add_child(_login_btn)
	_login_status = UiKitScript.label("未登录", 12, UiKitScript.MUTED)
	_login_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_login_row.add_child(_login_status)
	body.add_child(_login_row)

	var authlib_box := UiKitScript.hbox(6)
	_authlib_path = LineEdit.new()
	_authlib_path.editable = false
	_authlib_path.placeholder_text = "启动第三方登录所需的 authlib-injector.jar"
	_authlib_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_authlib_path.add_theme_font_size_override("font_size", 12)
	authlib_box.add_child(_authlib_path)
	_authlib_btn = UiKitScript.button("选择 authlib-injector.jar")
	_authlib_btn.pressed.connect(func() -> void: authlib_pick_requested.emit())
	authlib_box.add_child(_authlib_btn)
	_authlib_row = UiKitScript.field_row("注入器", authlib_box, 72)
	body.add_child(_authlib_row)

	_account_note = UiKitScript.wrapped_label("", 12, UiKitScript.MUTED)
	body.add_child(_account_note)
	return card

func _build_java_card() -> PanelContainer:
	var card := UiKitScript.card(10)
	var body := UiKitScript.vbox(8)
	card.add_child(body)
	body.add_child(UiKitScript.label("Java 设置", 15, UiKitScript.ACCENT))

	_java_auto = CheckBox.new()
	_java_auto.text = "自动选择 Java（推荐）"
	_java_auto.button_pressed = true
	_java_auto.toggled.connect(_on_java_auto_toggled)
	body.add_child(_java_auto)

	var path_row := HBoxContainer.new()
	path_row.add_theme_constant_override("separation", 8)
	_java_path = LineEdit.new()
	_java_path.editable = false
	_java_path.placeholder_text = "尚未检测到 Java"
	_java_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_row.add_child(_java_path)
	_java_manual_btn = UiKitScript.button("手动选择 java 可执行文件")
	_java_manual_btn.pressed.connect(func() -> void: manual_java_requested.emit())
	path_row.add_child(_java_manual_btn)
	body.add_child(path_row)

	var mem_row := HBoxContainer.new()
	mem_row.add_theme_constant_override("separation", 8)
	var mem_label := UiKitScript.label("最大内存", 13, UiKitScript.MUTED)
	mem_label.custom_minimum_size.x = 72
	mem_row.add_child(mem_label)
	_memory = SpinBox.new()
	_memory.min_value = 512
	_memory.max_value = 32768
	_memory.step = 256
	_memory.value = 2048
	_memory.suffix = " MB"
	_memory.custom_minimum_size.x = 150
	_memory.value_changed.connect(func(_value: float) -> void: _emit_changed())
	mem_row.add_child(_memory)
	mem_row.add_child(UiKitScript.spacer(true))
	body.add_child(mem_row)
	body.add_child(UiKitScript.wrapped_label(
		"自动设置 -Xmx/-Xms、-Dfile.encoding=UTF-8、natives、classpath 与版本自带 JVM 参数；第三方登录额外注入 authlib-injector。",
		11, UiKitScript.MUTED))

	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 8)
	_java_status = UiKitScript.wrapped_label("尚未检测 Java", 12, UiKitScript.MUTED)
	status_row.add_child(_java_status)
	_java_help = UiKitScript.button("怎么解决？")
	_java_help.visible = false
	_java_help.pressed.connect(func() -> void: java_help_requested.emit())
	status_row.add_child(_java_help)
	body.add_child(status_row)
	return card


func _build_instance_card() -> PanelContainer:
	var card := UiKitScript.card(10)
	var body := UiKitScript.vbox(8)
	card.add_child(body)
	body.add_child(UiKitScript.label("版本目录与组件", 15, UiKitScript.ACCENT))

	_component_summary = UiKitScript.wrapped_label("", 13, UiKitScript.TEXT)
	body.add_child(_component_summary)

	_auto_chinese = CheckBox.new()
	_auto_chinese.text = "启动时自动设置游戏中文（lang=zh_cn、Unicode 字体）"
	_auto_chinese.button_pressed = true
	_auto_chinese.toggled.connect(func(_on: bool) -> void: _emit_changed())
	body.add_child(_auto_chinese)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_open_instance_btn = UiKitScript.button("打开游戏目录")
	_open_instance_btn.pressed.connect(func() -> void: open_instance_requested.emit())
	row.add_child(_open_instance_btn)
	_manage_components_btn = UiKitScript.button("管理组件…")
	_manage_components_btn.pressed.connect(func() -> void: manage_components_requested.emit())
	row.add_child(_manage_components_btn)
	row.add_child(UiKitScript.spacer(true))
	body.add_child(row)

	_instance_hint = UiKitScript.wrapped_label("", 12, UiKitScript.MUTED)
	body.add_child(_instance_hint)
	return card


func _build_fx_card() -> PanelContainer:
	var card := UiKitScript.card(10)
	var body := UiKitScript.vbox(8)
	card.add_child(body)
	body.add_child(UiKitScript.label("界面动效", 15, UiKitScript.ACCENT))
	_reduce_motion = CheckBox.new()
	_reduce_motion.text = "减少动效（关闭位移/缩放，保留极短淡入）"
	_reduce_motion.button_pressed = bool(ConfigManager.reduce_motion)
	_reduce_motion.toggled.connect(func(_on: bool) -> void: _emit_changed())
	body.add_child(_reduce_motion)
	_low_spec = CheckBox.new()
	_low_spec.text = "低配模式（关闭 Shader/粒子类效果）"
	_low_spec.button_pressed = bool(ConfigManager.low_spec)
	_low_spec.toggled.connect(func(_on: bool) -> void: _emit_changed())
	body.add_child(_low_spec)
	body.add_child(UiKitScript.wrapped_label("说明书/免责声明保持静止，不参与动效。", 11, UiKitScript.MUTED))
	return card


func _build_resource_card() -> PanelContainer:
	var card := UiKitScript.card(10)
	var body := UiKitScript.vbox(8)
	card.add_child(body)
	body.add_child(UiKitScript.label("资源导入", 15, UiKitScript.ACCENT))
	var hint := UiKitScript.wrapped_label("只复制本地文件；同名文件会先备份为 .bak。", 12, UiKitScript.MUTED)
	body.add_child(hint)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(grid)
	var specs := [
		["导入整合包 (.mrpack)", import_mrpack_requested],
		["安装 Mod (.jar)", install_mod_requested],
		["安装光影 (.zip)", install_shader_requested],
		["安装材质 (.zip)", install_resource_requested],
	]
	for spec in specs:
		var b := UiKitScript.button(str(spec[0]))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var target_signal: Signal = spec[1]
		b.pressed.connect(func() -> void: target_signal.emit())
		grid.add_child(b)
		_resource_buttons.append(b)
	return card


func _build_action_bar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	_launch_btn = UiKitScript.accent_button("启动游戏")
	_launch_btn.custom_minimum_size.x = 150
	_launch_btn.custom_minimum_size.y = 36
	_launch_btn.pressed.connect(func() -> void: launch_requested.emit())
	bar.add_child(_launch_btn)
	_save_btn = UiKitScript.button("保存设置")
	_save_btn.custom_minimum_size.y = 36
	_save_btn.pressed.connect(func() -> void: save_requested.emit())
	bar.add_child(_save_btn)

	var status_box := UiKitScript.vbox(4)
	status_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress = ProgressBar.new()
	_progress.custom_minimum_size.y = 8
	_progress.show_percentage = false
	_progress.value = 0
	status_box.add_child(_progress)
	_status = UiKitScript.label("", 12, UiKitScript.MUTED)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_OFF
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.clip_text = true
	status_box.add_child(_status)
	bar.add_child(status_box)
	return bar


func set_version(entry: Dictionary, cfg, instance_dir: String, required_java: int) -> void:
	_last_java_result = {}
	if entry.is_empty():
		show_placeholder("尚未选择版本")
		return
	var version_id := str(entry.get("id", ""))
	_version_label.text = "版本 " + version_id
	if not bool(entry.get("usable", false)):
		_version_label.text = "版本 %s（不可用）" % version_id
		_enabled = false
		_account_note.text = ""
		_java_status.text = "该版本不可用：" + str(entry.get("reason", ""))
		_java_status.tooltip_text = str(entry.get("reason", "")) + "\n\n" + str(entry.get("fix_hint", ""))
		_java_status.add_theme_color_override("font_color", UiKitScript.ERROR)
		_java_help.visible = false
		_set_status("不可用：" + str(entry.get("reason", "")), "error")
		set_status_tooltip(str(entry.get("reason", "")) + "\n\n" + str(entry.get("fix_hint", "")))
		_refresh_controls()
		return
	if cfg == null:
		show_placeholder("无法载入该版本的实例设置")
		return
	_enabled = true
	_suppress = true
	_account_mode.select(_mode_index(str(cfg.account_mode)))
	_username.text = str(cfg.username)
	_auth_url.text = str(cfg.auth_url)
	_password.text = ""
	_authlib_path.text = str(cfg.authlib_jar)
	_authlib_path.tooltip_text = str(cfg.authlib_jar)
	_login_status.text = "未登录"
	_login_status.add_theme_color_override("font_color", UiKitScript.MUTED)
	_java_auto.set_pressed_no_signal(str(cfg.java_mode) == "auto")
	_java_path.text = str(cfg.java_path) if str(cfg.java_mode) == "manual" else ""
	_memory.value = int(cfg.max_memory_mb)
	_auto_chinese.set_pressed_no_signal(bool(cfg.auto_chinese))
	_reduce_motion.set_pressed_no_signal(bool(ConfigManager.reduce_motion))
	_low_spec.set_pressed_no_signal(bool(ConfigManager.low_spec))
	_current_version_id = version_id
	_component_summary.text = "存档 %d · Mod %d · 光影 %d · 材质 %d" % [
		int(entry.get("save_count", 0)), int(entry.get("mod_count", 0)),
		int(entry.get("shader_count", 0)), int(entry.get("resourcepack_count", 0)),
	]
	set_instance_dir(instance_dir)
	_on_account_mode_changed(_account_mode.selected)
	_on_java_auto_toggled(_java_auto.button_pressed)
	_suppress = false
	set_java_status_pending()
	set_status("已载入版本 %s，Java 要求：%d" % [version_id, required_java], "info")
	_refresh_controls()


func show_placeholder(message: String) -> void:
	_enabled = false
	_version_label.text = "尚未选择版本"
	if _account_note != null:
		_account_note.text = ""
	if _java_status != null:
		_java_status.text = message
		_java_status.add_theme_color_override("font_color", UiKitScript.MUTED)
	if _java_help != null:
		_java_help.visible = false
	_last_java_result = {}
	if _instance_hint != null:
		_instance_hint.text = ""
	if _component_summary != null:
		_component_summary.text = ""
	_refresh_controls()
	set_status(message, "info")


func apply_to(cfg) -> void:
	cfg.account_mode = _mode_from_index(_account_mode.selected)
	cfg.username = _username.text.strip_edges()
	cfg.auth_url = _auth_url.text.strip_edges()
	cfg.authlib_jar = _authlib_path.text.strip_edges()
	cfg.java_mode = "auto" if _java_auto.button_pressed else "manual"
	cfg.java_path = _java_path.text.strip_edges()
	# 实例已经固定跟随版本目录，不再保存实例名/目录模式。
	cfg.game_dir_mode = "version"
	cfg.isolate = true
	cfg.max_memory_mb = int(_memory.value)
	cfg.auto_chinese = _auto_chinese.button_pressed
	ConfigManager.reduce_motion = _reduce_motion.button_pressed
	ConfigManager.low_spec = _low_spec.button_pressed


func set_instance_dir(instance_dir: String) -> void:
	if _instance_hint == null:
		return
	_instance_hint.text = "版本目录：%s（设置保存在该目录的 %s）" % [
		ProjectSettings.globalize_path(instance_dir).replace("\\", "/"),
		InstanceConfigScript.VERSION_CONFIG_NAME,
	]
	_instance_hint.tooltip_text = ProjectSettings.globalize_path(instance_dir).replace("\\", "/")


func set_java_status_pending() -> void:
	_java_status.text = "正在检测 Java…"
	_java_status.add_theme_color_override("font_color", UiKitScript.MUTED)
	_java_help.visible = false
	_last_java_result = {}


func set_java_status(result: Dictionary, required_java: int) -> void:
	_last_java_result = result
	if bool(result.get("ok", false)):
		_java_path.text = str(result.get("path", ""))
		var major := int(result.get("major", 0))
		if bool(result.get("meets_requirement", true)):
			_java_status.text = "Java %d 可用：%s" % [major, str(result.get("version_text", ""))]
			_java_status.add_theme_color_override("font_color", UiKitScript.SUCCESS)
			_java_help.visible = false
			_java_status.tooltip_text = str(result.get("path", ""))
		else:
			_java_status.text = "检测到 Java %d，但该版本要求 Java %d。请更换 Java。" % [major, required_java]
			_java_status.add_theme_color_override("font_color", UiKitScript.ERROR)
			_java_help.visible = true
			var err: Dictionary = result.get("error", {})
			_java_status.tooltip_text = str(err.get("message", "")) + "\n" + str(err.get("fix_hint", ""))
	else:
		var err2: Dictionary = result.get("error", {})
		_java_status.text = str(err2.get("title", "未找到可用的 Java")) + "。请点击「怎么解决？」查看建议。"
		_java_status.add_theme_color_override("font_color", UiKitScript.ERROR)
		_java_help.visible = true
		_java_status.tooltip_text = str(err2.get("message", "")) + "\n" + str(err2.get("fix_hint", ""))


func set_java_mode_manual(path: String) -> void:
	_java_auto.set_pressed_no_signal(false)
	_java_path.text = path
	_on_java_auto_toggled(false)


func get_java_mode() -> String:
	return "auto" if _java_auto.button_pressed else "manual"


func get_java_path() -> String:
	return _java_path.text.strip_edges()


func last_java_result() -> Dictionary:
	return _last_java_result


func focus_username() -> void:
	if _username != null and _username.editable:
		_username.grab_focus()


func get_thirdparty_password() -> String:
	return _password.text if _password != null else ""


func set_ms_status(text: String, kind: String = "info") -> void:
	if _ms_status == null:
		return
	_ms_status.text = text
	var color := UiKitScript.MUTED
	match kind:
		"success":
			color = UiKitScript.SUCCESS
		"error":
			color = UiKitScript.ERROR
		"warn":
			color = UiKitScript.WARN
		"info":
			color = UiKitScript.TEXT
	_ms_status.add_theme_color_override("font_color", color)


func set_ms_busy(busy: bool) -> void:
	_ms_busy = busy
	if _ms_login_btn != null:
		_ms_login_btn.text = "登录中…" if busy else "登录正版"
	_refresh_controls()


func set_ms_code(code: String, uri: String) -> void:
	_ms_verify_uri = uri.strip_edges()
	if _ms_code == null:
		return
	_ms_code.text = code
	_ms_code.caret_column = 0
	_ms_code_row.visible = _account_mode.selected == 0
	if not code.is_empty():
		set_ms_status("请在浏览器输入验证码：" + code, "info")
	_refresh_controls()


func clear_ms_code() -> void:
	if _ms_code != null:
		_ms_code.text = ""
	if _ms_code_row != null:
		_ms_code_row.visible = _account_mode.selected == 0
	_ms_verify_uri = ""
	_refresh_controls()


func _copy_ms_code() -> void:
	if _ms_code == null or _ms_code.text.is_empty():
		set_ms_status("还没有验证码，请先点「登录正版」。", "info")
		return
	DisplayServer.clipboard_set(_ms_code.text)
	set_ms_status("验证码已复制，请粘贴到 Microsoft 登录页。", "success")


func _open_ms_browser() -> void:
	var uri := _ms_verify_uri
	if uri.is_empty():
		uri = "https://www.microsoft.com/link"
	var err := OS.shell_open(uri)
	if err != OK:
		set_ms_status("无法打开浏览器，请手动访问：%s" % uri, "warn")


func _open_auth_site() -> void:
	var base := _auth_url.text.strip_edges().trim_suffix("/")
	for suffix in ["/authserver/authenticate", "/authserver", "/api/yggdrasil"]:
		if base.ends_with(suffix):
			base = base.trim_suffix(suffix)
	var scheme_end := base.find("://")
	if scheme_end >= 0:
		var slash := base.find("/", scheme_end + 3)
		if slash >= 0:
			base = base.substr(0, slash)
	if base.is_empty():
		_account_note.text = "认证地址为空，无法打开认证网站。"
		return
	OS.shell_open(base)


func clear_password() -> void:
	if _password != null:
		_password.text = ""


func get_authlib_jar() -> String:
	return _authlib_path.text.strip_edges() if _authlib_path != null else ""


func set_authlib_jar(path: String) -> void:
	if _authlib_path != null:
		_authlib_path.text = path
		_authlib_path.tooltip_text = path


func set_username(name: String) -> void:
	if _username != null:
		_username.text = name


func set_account_mode(mode: String) -> void:
	if _account_mode == null:
		return
	_account_mode.select(_mode_index(mode))
	_on_account_mode_changed(_account_mode.selected)


func set_login_status(text: String, kind: String = "info") -> void:
	if _login_status == null:
		return
	_login_status.text = text
	var color := UiKitScript.MUTED
	match kind:
		"success":
			color = UiKitScript.SUCCESS
		"error":
			color = UiKitScript.ERROR
		"warn":
			color = UiKitScript.WARN
		"info":
			color = UiKitScript.TEXT
	_login_status.add_theme_color_override("font_color", color)


func set_login_busy(busy: bool) -> void:
	_login_busy = busy
	if _login_btn != null:
		_login_btn.text = "登录中…" if busy else "登录第三方"
	_refresh_controls()

func set_status(text: String, kind: String = "info") -> void:
	if _status == null:
		return
	_status.text = text
	_status.tooltip_text = text
	var color := UiKitScript.MUTED
	match kind:
		"success":
			color = UiKitScript.SUCCESS
		"error":
			color = UiKitScript.ERROR
		"warn":
			color = UiKitScript.WARN
		"info":
			color = UiKitScript.TEXT
	_status.add_theme_color_override("font_color", color)


func set_progress(value: int, message: String = "") -> void:
	if _progress == null:
		return
	_progress.value = clampi(value, 0, 100)
	if _launch_btn != null and _launch_btn.has_method("set_launch_progress"):
		_launch_btn.set_launch_progress(float(_progress.value) / 100.0, _progress.value > 0 and _progress.value < 100)
	if not message.is_empty():
		set_status(message, "info")


func play_launch_success() -> void:
	if _launch_btn != null and _launch_btn.has_method("set_launch_progress"):
		_launch_btn.set_launch_progress(1.0, true)
		_launch_btn.play_success()


func play_launch_failure() -> void:
	if _launch_btn != null and _launch_btn.has_method("set_launch_progress"):
		_launch_btn.set_launch_progress(0.0, false)
		_launch_btn.play_failure()


func set_status_tooltip(text: String) -> void:
	if _status != null:
		_status.tooltip_text = text


func set_busy(busy: bool) -> void:
	_busy = busy
	if not busy and not _running:
		_progress.value = 0
	_refresh_controls()


func set_running(running: bool) -> void:
	_running = running
	if running:
		_launch_btn.text = "游戏运行中…"
	else:
		_launch_btn.text = "启动游戏"
	_refresh_controls()


func set_launch_enabled(enabled: bool) -> void:
	_enabled = enabled
	_refresh_controls()


func _refresh_controls() -> void:
	if _launch_btn == null:
		return
	var editable := _enabled and not _busy and not _running and not _login_busy and not _ms_busy
	_account_mode.disabled = not editable
	_username.editable = editable
	_ms_login_btn.disabled = not editable or _account_mode.selected != 0
	_ms_code.editable = false
	_ms_copy_btn.disabled = false
	_ms_open_btn.disabled = false
	_auth_url.editable = editable and _account_mode.selected == 2
	_password.editable = editable and _account_mode.selected == 2
	_authlib_path.editable = false
	_authlib_btn.disabled = not editable or _account_mode.selected != 2
	_login_btn.disabled = not editable or _account_mode.selected != 2
	_java_auto.disabled = not editable
	_java_manual_btn.disabled = not editable or _java_auto.button_pressed
	_java_help.disabled = not editable
	_memory.editable = editable
	_auto_chinese.disabled = not editable
	_reduce_motion.disabled = not editable
	_low_spec.disabled = not editable
	_open_instance_btn.disabled = not editable
	_manage_components_btn.disabled = not editable
	for b in _resource_buttons:
		b.disabled = not editable
	_save_btn.disabled = not editable
	_launch_btn.disabled = not _enabled or _busy or _running or _login_busy or _ms_busy


func _on_account_mode_changed(_index: int) -> void:
	var mode := _mode_from_index(_account_mode.selected)
	var premium_path := ProjectSettings.globalize_path(ConfigManager.auth_dir() + "/premium.json").replace("\\", "/")
	var third_path := ProjectSettings.globalize_path(ConfigManager.auth_dir() + "/thirdparty.json").replace("\\", "/")
	var third := mode == "thirdparty"
	var online := mode == "online"
	if not third and _password != null:
		_password.text = ""
	if _auth_row != null:
		_auth_row.visible = third
	if _password_row != null:
		_password_row.visible = third
	if _login_row != null:
		_login_row.visible = third
	if _authlib_row != null:
		_authlib_row.visible = third
	if _ms_login_row != null:
		_ms_login_row.visible = online
	if _ms_code_row != null:
		_ms_code_row.visible = online
	match mode:
		"offline":
			_account_note.text = "离线模式：用本地生成的标识启动，仅适合单人游戏或允许离线登录的服务器。"
		"online":
			_account_note.text = "正版 Microsoft 登录：点击「登录正版」后，启动器会显示验证码并打开 microsoft.com/link，输入验证码完成登录；随后自动查询 Xbox/Minecraft。无需填写 Azure client_id。成功后令牌保存在 %s。" % premium_path
		_:
			_account_note.text = "第三方 Yggdrasil：支持邮箱或用户名 + 密码登录；密码只发送到上方认证地址，不保存；令牌保存在 %s。authlib-injector.jar 是本地 Java 代理，把 Mojang 认证请求重定向到该 Yggdrasil 服务器；邮箱验证/2FA 需先在认证网站完成。" % third_path
	_refresh_controls()
	_emit_changed()


func _on_java_auto_toggled(pressed: bool) -> void:
	if _java_manual_btn != null:
		_java_manual_btn.disabled = pressed or not _enabled or _busy or _running
	if pressed and _java_path != null and not _busy:
		_java_path.text = ""
	if _enabled and not _busy and not _suppress:
		java_mode_changed.emit()
		_emit_changed()


func _set_status(text: String, kind: String) -> void:
	set_status(text, kind)


func _emit_changed() -> void:
	if not _suppress:
		changed.emit()


static func _mode_index(mode: String) -> int:
	match mode:
		"online":
			return 0
		"offline":
			return 1
		_:
			return 2


static func _mode_from_index(index: int) -> String:
	match index:
		0:
			return "online"
		1:
			return "offline"
		_:
			return "thirdparty"
