extends Control
## 主界面控制器：串联版本扫描、实例设置、Java 检测、启动、资源导入与对话框。

const UiKitScript = preload("res://scripts/ui/ui_kit.gd")
const VersionScannerScript = preload("res://scripts/core/version_scanner.gd")
const InstanceConfigScript = preload("res://scripts/core/instance_config.gd")
const JavaManagerScript = preload("res://scripts/core/java_manager.gd")
const LaunchBuilderScript = preload("res://scripts/core/launch_builder.gd")
const VersionPanelScript = preload("res://scripts/ui/version_panel.gd")
const SettingsPanelScript = preload("res://scripts/ui/settings_panel.gd")
const BottomBarScript = preload("res://scripts/ui/bottom_bar.gd")
const DialogsScript = preload("res://scripts/ui/dialogs.gd")
const ProcessRunnerScript = preload("res://scripts/core/process_runner.gd")
const ResourceInstallerScript = preload("res://scripts/core/resource_installer.gd")
const MrpackImporterScript = preload("res://scripts/core/mrpack_importer.gd")
const ComponentManagerScript = preload("res://scripts/core/component_manager.gd")
const OnlineAuthScript = preload("res://scripts/core/online_auth.gd")
const MicrosoftAuthScript = preload("res://scripts/core/microsoft_auth.gd")
const AuthHelperScript = preload("res://scripts/core/auth_helper.gd")
const ErrorInfoScript = preload("res://scripts/core/error_info.gd")
const FileUtilsScript = preload("res://scripts/core/file_utils.gd")
const ThreadTaskScript = preload("res://scripts/core/thread_task.gd")

var _root := ""
var _roots: Array[String] = []
var _versions: Array[Dictionary] = []
var _selected: Dictionary = {}
var _cfg = null
var _instance_dir := ""
var _java_result: Dictionary = {}
var _java_seq := 0
var _running := false
var _busy := false

var _root_edit: LineEdit
var _root_label: Label
var _remove_root_btn: Button
var _body: Control
var _version_panel
var _settings_panel
var _bottom_bar
var _dialogs
var _process_runner
var _installer
var _importer
var _online_auth
var _ms_auth

var _scan_task: Node
var _java_task: Node
var _launch_task: Node
var _probe_task: Node
var _autosave_timer: Timer
var _pending_mrpack := ""


func _ready() -> void:
	theme = UiKitScript.make_theme()
	get_window().title = "gl启动器"
	_build_ui()
	_add_services()
	_connect_signals()

	_root = str(ConfigManager.game_root)
	_roots.clear()
	for root in ConfigManager.game_roots:
		_roots.append(str(root))
	_update_root_display()
	LogManager.info("=== 启动器界面已就绪 ===")
	LogManager.info("游戏文件夹：%s" % ", ".join(_roots))
	if not str(ConfigManager.config_load_error).is_empty():
		LogManager.warn(str(ConfigManager.config_load_error))
	call_deferred("_play_intro")
	_scan_versions()


func _play_intro() -> void:
	if _body == null or bool(ConfigManager.reduce_motion):
		return
	_body.pivot_offset = _body.size * 0.5
	_body.modulate.a = 0.0
	_body.scale = Vector2(0.97, 0.97)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_body, "modulate:a", 1.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_body, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = UiKitScript.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var root_box := UiKitScript.vbox(10)
	margin.add_child(root_box)
	root_box.add_child(_build_topbar())

	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.split_offset = 430
	root_box.add_child(body)

	_body = body
	_version_panel = VersionPanelScript.new()
	body.add_child(_version_panel)
	_version_panel.build()

	_settings_panel = SettingsPanelScript.new()
	body.add_child(_settings_panel)
	_settings_panel.build()

	_bottom_bar = BottomBarScript.new()
	_bottom_bar.custom_minimum_size.y = 38
	_bottom_bar.size_flags_vertical = Control.SIZE_FILL
	root_box.add_child(_bottom_bar)
	_bottom_bar.build()


func _build_topbar() -> Control:
	var card := UiKitScript.card(10)
	var row := UiKitScript.hbox(10)
	card.add_child(row)
	var title := UiKitScript.label("gl启动器", 22, UiKitScript.ACCENT)
	title.custom_minimum_size.x = 130
	row.add_child(title)
	row.add_child(UiKitScript.spacer(true))
	var choose_btn := UiKitScript.button("添加文件夹")
	choose_btn.pressed.connect(_choose_root)
	row.add_child(choose_btn)
	_remove_root_btn = UiKitScript.button("移除当前文件夹")
	_remove_root_btn.pressed.connect(_remove_current_root)
	row.add_child(_remove_root_btn)
	var logs_btn := UiKitScript.button("打开日志目录")
	logs_btn.pressed.connect(func() -> void: LogManager.open_logs_folder())
	row.add_child(logs_btn)
	return card


func _add_services() -> void:
	_dialogs = DialogsScript.new()
	add_child(_dialogs)
	_process_runner = ProcessRunnerScript.new()
	add_child(_process_runner)
	_installer = ResourceInstallerScript.new()
	add_child(_installer)
	_importer = MrpackImporterScript.new()
	add_child(_importer)
	_online_auth = OnlineAuthScript.new()
	add_child(_online_auth)
	_ms_auth = MicrosoftAuthScript.new()
	add_child(_ms_auth)
	_autosave_timer = Timer.new()
	_autosave_timer.one_shot = true
	_autosave_timer.wait_time = 0.45
	_autosave_timer.timeout.connect(_on_autosave_timeout)
	add_child(_autosave_timer)


func _connect_signals() -> void:
	_version_panel.refresh_requested.connect(_scan_versions)
	_version_panel.version_chosen.connect(_on_version_chosen)
	_version_panel.version_activated.connect(_on_version_activated)
	_version_panel.root_selected.connect(_on_root_selected)
	_settings_panel.save_requested.connect(func() -> void: _save_settings(false))
	_settings_panel.launch_requested.connect(_launch)
	_settings_panel.manual_java_requested.connect(_on_manual_java_requested)
	_settings_panel.java_mode_changed.connect(_detect_java)
	_settings_panel.java_help_requested.connect(_on_java_help_requested)
	_settings_panel.open_instance_requested.connect(_open_instance_dir)
	_settings_panel.import_mrpack_requested.connect(_on_import_mrpack_requested)
	_settings_panel.install_mod_requested.connect(func() -> void: _pick_resource_files("mod"))
	_settings_panel.install_shader_requested.connect(func() -> void: _pick_resource_files("shader"))
	_settings_panel.install_resource_requested.connect(func() -> void: _pick_resource_files("resource"))
	_settings_panel.thirdparty_login_requested.connect(_on_thirdparty_login_requested)
	_settings_panel.authlib_pick_requested.connect(_on_authlib_pick_requested)
	_settings_panel.premium_login_requested.connect(_on_premium_login_requested)
	_settings_panel.manage_components_requested.connect(_on_manage_components_requested)
	_settings_panel.changed.connect(_schedule_autosave)
	_online_auth.finished.connect(_on_thirdparty_login_finished)
	_online_auth.status_changed.connect(func(message: String) -> void:
		_settings_panel.set_login_status(message, "info")
	)
	_ms_auth.code_ready.connect(_on_ms_code_ready)
	_ms_auth.finished.connect(_on_ms_login_finished)
	_ms_auth.status_changed.connect(func(message: String) -> void:
		_settings_panel.set_ms_status(message, "info")
	)
	_dialogs.files_picked.connect(_on_files_picked)
	_dialogs.dir_picked.connect(_on_dir_picked)
	_dialogs.mrpack_target_confirmed.connect(_run_mrpack_import)
	_dialogs.confirm_accepted.connect(_on_confirm_accepted)
	_dialogs.components_confirmed.connect(_on_components_confirmed)
	_installer.progress.connect(_on_install_progress)
	_installer.finished.connect(_on_resources_finished)
	_importer.progress.connect(_on_install_progress)
	_importer.finished.connect(_on_mrpack_finished)
	_process_runner.process_finished.connect(_on_process_finished)
	ErrorReporter.error_raised.connect(_on_error_raised)


func _update_root_display() -> void:
	if _remove_root_btn != null:
		_remove_root_btn.disabled = _roots.is_empty()


func _choose_root() -> void:
	_dialogs.pick_dir("game_root", "添加游戏文件夹（选择包含 versions 的目录）", _display_path(_root))


func _on_dir_picked(role: String, path: String) -> void:
	if role == "mrpack_source":
		_run_mrpack_import(_instance_dir, path)
		return
	if role != "game_root":
		return
	var resolved := ConfigManager.resolve_game_root(path)
	if resolved != path:
		LogManager.info("已在所选目录下自动定位 .minecraft：%s" % resolved)
	if _roots.has(resolved):
		_settings_panel.set_status("该游戏文件夹已经添加：%s" % resolved, "warn")
		return
	var added := ConfigManager.add_game_root(resolved)
	if added:
		_roots.append(resolved)
		_root = resolved
		_update_root_display()
		_settings_panel.set_status("已添加游戏文件夹：" + _display_path(resolved), "success")
		LogManager.info("已添加游戏文件夹：%s" % resolved)
		_scan_versions()


func _remove_current_root() -> void:
	var target: String = _version_panel.selected_root()
	if target.is_empty():
		target = _root
	if target.is_empty():
		return
	_dialogs.confirm_action("remove_root|" + target, "移除游戏文件夹",
		"确定移除这个游戏文件夹吗？\n\n" + _display_path(target) +
		"\n\n只会取消启动器中的记录，不会删除磁盘上的任何文件。")


func _do_remove_root(target: String) -> void:
	if not ConfigManager.remove_game_root(target):
		return
	_roots.erase(target)
	_root = _roots[0] if not _roots.is_empty() else ""
	_selected = {}
	_cfg = null
	_instance_dir = ""
	_update_root_display()
	_settings_panel.show_placeholder("已移除游戏文件夹，请选择版本")
	_settings_panel.set_launch_enabled(false)
	LogManager.info("已移除游戏文件夹：%s" % target)
	_scan_versions()


func _on_confirm_accepted(action: String) -> void:
	if action.begins_with("remove_root|"):
		_do_remove_root(action.trim_prefix("remove_root|"))


func _on_manage_components_requested() -> void:
	if _cfg == null or _instance_dir.is_empty():
		return
	if _running or _busy:
		_settings_panel.set_status("游戏运行或后台任务进行中，暂时不能移出组件。", "warn")
		return
	var info: Dictionary = ComponentManagerScript.list_components(_instance_dir)
	var items: Array = info.get("items", [])
	if items.is_empty():
		_settings_panel.set_status("这个版本没有可移出的 Mod/光影/材质/存档。", "info")
		return
	_dialogs.show_components(info)


func _on_components_confirmed(paths: PackedStringArray) -> void:
	if _cfg == null or _instance_dir.is_empty():
		return
	var result: Dictionary = ComponentManagerScript.move_selected(_instance_dir, _root, str(_cfg.version_id), paths)
	var moved: Array = result.get("moved", [])
	var errors: Array = result.get("errors", [])
	var target := str(result.get("target", ""))
	if not errors.is_empty():
		var lines: Array[String] = ["移出过程中出现问题："]
		for i in range(mini(10, errors.size())):
			lines.append("  " + str(errors[i]))
		_dialogs.show_report("组件移出结果", "\n".join(lines), "\n".join(lines))
	if not moved.is_empty():
		var message := "已移出 %d 个组件。\n\n备份位置（.minecraft 外面）：\n%s" % [moved.size(), target]
		_dialogs.show_report("组件已移出", message, message)
		_settings_panel.set_status("已移出 %d 个组件到：%s" % [moved.size(), target], "success")
		LogManager.info("组件已移出：%d 个 -> %s" % [moved.size(), target])
		_scan_versions()


func _copy_root_path() -> void:
	if _roots.is_empty():
		return
	var lines: Array[String] = []
	for root in _roots:
		lines.append(_display_path(root))
	DisplayServer.clipboard_set("\n".join(lines))
	LogManager.info("已复制游戏文件夹列表到剪贴板")


func _scan_versions() -> void:
	if _scan_task != null:
		LogManager.info("扫描仍在进行，请稍候")
		return
	if _roots.is_empty():
		_version_panel.set_scan_result({"ok": true, "versions": [], "roots": [], "errors": []})
		_settings_panel.show_placeholder("请先添加游戏文件夹")
		_settings_panel.set_status("尚未添加游戏文件夹。", "warn")
		return
	_version_panel.show_loading()
	_settings_panel.set_status("正在扫描 versions 目录…", "info")
	var roots := PackedStringArray(_roots)
	var task = ThreadTaskScript.new()
	add_child(task)
	_scan_task = task
	task.finished.connect(_on_scan_finished)
	task.start(func() -> Dictionary:
		return VersionScannerScript.scan_roots(roots)
	)


func _on_scan_finished(result: Variant) -> void:
	_scan_task = null
	var res: Dictionary = result if result is Dictionary else {"ok": false, "versions": [], "roots": _roots, "errors": []}
	_version_panel.set_scan_result(res)
	_versions.clear()
	var raw: Array = res.get("versions", [])
	for v in raw:
		if v is Dictionary:
			_versions.append(v)
	if not bool(res.get("ok", false)):
		var err: Dictionary = res.get("error", {})
		_settings_panel.show_placeholder("无法读取版本目录")
		ErrorReporter.report_error(err)
		return
	var errors: Array = res.get("errors", [])
	for i in range(mini(3, errors.size())):
		var err: Dictionary = errors[i]
		LogManager.warn("游戏文件夹扫描失败：%s" % str(err.get("message", "")))
	if not errors.is_empty() and _versions.is_empty():
		var first: Dictionary = errors[0]
		_settings_panel.show_placeholder("无法读取游戏文件夹")
		ErrorReporter.report_error(first)
		return
	var usable := VersionScannerScript.usable_count(_versions)
	LogManager.info("扫描完成：%d 个文件夹，%d 个版本，%d 个可用" % [_roots.size(), _versions.size(), usable])
	if _versions.is_empty():
		_settings_panel.show_placeholder("未发现版本，请检查 versions 目录")
		_settings_panel.set_status("未发现版本。请检查各游戏文件夹的 versions 目录。", "warn")
		return
	var target := _pick_auto_version()
	if not target.is_empty():
		_root = str(target.get("root", _root))
		ConfigManager.set_current_root(_root)
		_update_root_display()
		_version_panel.select_version(str(target.get("id", "")), _root)


func _pick_auto_version() -> Dictionary:
	for v in _versions:
		if (str(v.get("id", "")) == ConfigManager.last_version
				and str(v.get("root", "")) == ConfigManager.last_root
				and bool(v.get("usable", false))):
			return v
	for v in _versions:
		if str(v.get("id", "")) == ConfigManager.last_version and bool(v.get("usable", false)):
			return v
	for v in _versions:
		if bool(v.get("usable", false)):
			return v
	if not _versions.is_empty():
		return _versions[0]
	return {}


func _on_root_selected(root: String) -> void:
	if root.is_empty():
		return
	_root = root
	ConfigManager.set_current_root(root)
	_update_root_display()
	_selected = {}
	_cfg = null
	_instance_dir = ""
	_settings_panel.show_placeholder("已选择游戏文件夹，请在左侧展开并选择版本")
	_settings_panel.set_status("游戏文件夹：" + _display_path(root), "info")
	_settings_panel.set_launch_enabled(false)


func _on_version_chosen(entry: Dictionary) -> void:
	_autosave_timer.stop()
	if _cfg != null and not _selected.is_empty() and not _instance_dir.is_empty():
		_save_settings(true)
	_selected = entry.duplicate(true)
	_root = str(entry.get("root", _root))
	ConfigManager.set_current_root(_root)
	_update_root_display()
	_java_seq += 1
	_java_result = {}
	if not bool(_selected.get("usable", false)):
		_cfg = null
		_instance_dir = ""
		_settings_panel.set_version(_selected, null, "", int(_selected.get("required_java", 8)))
		_settings_panel.set_launch_enabled(false)
		LogManager.warn("选择了不可用版本：%s（%s）" % [_selected.get("id", ""), _selected.get("reason", "")])
		return
	var version_id := str(_selected.get("id", ""))
	_instance_dir = str(_selected.get("dir", ""))
	var loaded := InstanceConfigScript.load_for_version(_instance_dir, version_id, _root)
	var cfg
	if bool(loaded.get("found", false)):
		cfg = loaded.get("config", null)
	else:
		# 旧版本把实例放在 user://instances；第一次打开时迁移到版本目录。
		var legacy := InstanceConfigScript.find_for_version(ConfigManager.instances_dir(), version_id, _root)
		if bool(legacy.get("found", false)):
			cfg = legacy.get("config", null)
			LogManager.info("已把旧实例设置迁移到版本目录：%s" % _display_path(_instance_dir))
		else:
			cfg = InstanceConfigScript.create(version_id)
			cfg.username = ConfigManager.last_username
			cfg.java_mode = ConfigManager.java_mode
			cfg.java_path = ConfigManager.java_path
			cfg.max_memory_mb = ConfigManager.max_memory_mb
		cfg.instance_dir = _instance_dir
		cfg.source_root = _root
		cfg.save_to(_instance_dir)
	cfg.instance_dir = _instance_dir
	cfg.source_root = _root
	if str(cfg.authlib_jar).strip_edges().is_empty():
		cfg.authlib_jar = AuthHelperScript.find_authlib_jar(_root)
	if str(cfg.auth_url).strip_edges().is_empty():
		cfg.auth_url = AuthHelperScript.read_pcl_auth_server(_root, version_id)
	_cfg = cfg
	_settings_panel.set_version(_selected, cfg, _instance_dir, int(_selected.get("required_java", 8)))
	_settings_panel.set_launch_enabled(true)
	if bool(_selected.get("has_game_data", false)):
		_settings_panel.set_status("游戏目录固定为版本文件夹，可直接读取 saves/ 与 mods/。", "info")
	_refresh_login_status(cfg)
	_detect_java()


func _refresh_login_status(cfg) -> void:
	if cfg == null:
		return
	if str(cfg.account_mode) == "online":
		var premium_path := ConfigManager.auth_dir() + "/premium.json"
		if FileAccess.file_exists(premium_path):
			var f := FileAccess.open(premium_path, FileAccess.READ)
			var name := ""
			if f != null:
				var parser := JSON.new()
				if parser.parse(f.get_as_text()) == OK and parser.data is Dictionary:
					name = str(parser.data.get("name", ""))
				f.close()
			_settings_panel.set_ms_status("已保存令牌" + (("：" + name) if not name.is_empty() else ""), "success")
		else:
			_settings_panel.set_ms_status("未登录", "info")
		return
	if str(cfg.account_mode) != "thirdparty":
		return
	var token_path := AuthHelperScript.thirdparty_token_path()
	if FileAccess.file_exists(token_path):
		var f := FileAccess.open(token_path, FileAccess.READ)
		var name := ""
		if f != null:
			var parser := JSON.new()
			if parser.parse(f.get_as_text()) == OK and parser.data is Dictionary:
				name = str(parser.data.get("name", ""))
			f.close()
		_settings_panel.set_login_status("已保存令牌" + (("：" + name) if not name.is_empty() else ""), "success")
	elif str(cfg.authlib_jar).strip_edges().is_empty():
		_settings_panel.set_login_status("未登录；未找到 authlib-injector.jar", "warn")
	else:
		_settings_panel.set_login_status("未登录", "info")


func _on_version_activated(_entry: Dictionary) -> void:
	_settings_panel.focus_username()


func _detect_java() -> void:
	if _cfg == null or _selected.is_empty() or not bool(_selected.get("usable", false)):
		return
	var required := int(_selected.get("required_java", 8))
	var mode: String = _settings_panel.get_java_mode()
	var preferred: String = _settings_panel.get_java_path() if mode == "manual" else ""
	_java_seq += 1
	var seq := _java_seq
	_settings_panel.set_java_status_pending()
	if mode == "manual" and preferred.is_empty():
		var err := ErrorInfoScript.make("JAVA_NOT_FOUND", {"hint": JavaManagerScript.install_hint(), "path": JavaManagerScript.suggested_path()})
		_settings_panel.set_java_status({"ok": false, "error": err}, required)
		_settings_panel.set_status("请先点击「手动选择 java 可执行文件」。", "warn")
		return
	var task = ThreadTaskScript.new()
	add_child(task)
	_java_task = task
	var root := _root
	task.finished.connect(_on_java_detected.bind(seq, required))
	task.start(func() -> Dictionary:
		return JavaManagerScript.find_java(required, preferred, root)
	)


func _on_java_detected(result: Variant, seq: int, required: int) -> void:
	if seq != _java_seq:
		return
	_java_task = null
	var res: Dictionary = result if result is Dictionary else {"ok": false}
	_java_result = res
	_settings_panel.set_java_status(res, required)
	if bool(res.get("ok", false)):
		if bool(res.get("meets_requirement", true)):
			LogManager.info("Java 检测成功：%s（Java %d）" % [str(res.get("path", "")), int(res.get("major", 0))])
			_settings_panel.set_status("Java %d 可用，可以启动游戏。" % int(res.get("major", 0)), "success")
		else:
			LogManager.warn("Java 版本过低：检测到 %d，要求 %d" % [int(res.get("major", 0)), required])
			_settings_panel.set_status("Java 版本过低，请安装 Java %d 或更高版本，或手动选择。" % required, "error")
	else:
		var err: Dictionary = res.get("error", {})
		LogManager.warn("Java 检测失败：%s" % str(err.get("title", "未找到 Java")))
		_settings_panel.set_status("未找到可用的 Java，请安装或点击「手动选择 java 可执行文件」。", "error")


func _on_manual_java_requested() -> void:
	var filters := PackedStringArray(["java.exe ; Java 可执行文件", "*.exe ; 可执行文件", "* ; 所有文件"])
	if OS.get_name() != "Windows":
		filters = PackedStringArray(["* ; 所有文件"])
	_dialogs.pick_files("java", "选择 java 可执行文件", filters, false)


func _on_files_picked(role: String, paths: PackedStringArray) -> void:
	if paths.is_empty():
		return
	match role:
		"java":
			_validate_manual_java(paths[0])
		"mrpack":
			_pending_mrpack = paths[0]
			_show_mrpack_target()
		"mod":
			_install_resources("mod", paths)
		"shader":
			_install_resources("shader", paths)
		"resource":
			_install_resources("resource", paths)
		"authlib":
			_set_authlib_jar(paths[0])


func _validate_manual_java(path: String) -> void:
	if _cfg == null:
		return
	_settings_panel.set_status("正在验证 Java：%s" % path, "info")
	var java_path := path
	var task = ThreadTaskScript.new()
	add_child(task)
	_probe_task = task
	task.finished.connect(_on_manual_java_probed.bind(path))
	task.start(func() -> Dictionary:
		return JavaManagerScript.probe(java_path)
	)


func _on_manual_java_probed(result: Variant, path: String) -> void:
	_probe_task = null
	if _cfg == null or _selected.is_empty():
		return
	var res: Dictionary = result if result is Dictionary else {"ok": false}
	if not bool(res.get("ok", false)):
		ErrorReporter.report_error(res.get("error", ErrorInfoScript.make("JAVA_NOT_RUNNABLE", {"path": path, "detail": "未知"})))
		return
	_cfg.java_mode = "manual"
	_cfg.java_path = path
	_settings_panel.set_java_mode_manual(path)
	var required := int(_selected.get("required_java", 8))
	res["meets_requirement"] = int(res.get("major", 0)) >= required
	if not bool(res["meets_requirement"]):
		res["error"] = ErrorInfoScript.make("JAVA_TOO_OLD", {
			"path": path,
			"detected": str(res.get("major", 0)),
			"required": str(required),
		})
	_settings_panel.set_java_status(res, required)
	LogManager.info("已手动选择 Java：%s" % path)
	_save_settings(true)
	_detect_java()


func _on_java_help_requested() -> void:
	var err: Variant = _java_result.get("error", {})
	if not (err is Dictionary) or err.is_empty():
		err = ErrorInfoScript.make("JAVA_NOT_FOUND", {"hint": JavaManagerScript.install_hint(), "path": JavaManagerScript.suggested_path()})
	ErrorReporter.report_error(err)


func _on_authlib_pick_requested() -> void:
	if _cfg == null:
		return
	_dialogs.pick_files("authlib", "选择 authlib-injector.jar", PackedStringArray([
		"*authlib-injector*.jar ; authlib-injector",
		"*.jar ; JAR 文件",
	]), false, _display_path(_root))


func _set_authlib_jar(path: String) -> void:
	if _cfg == null:
		return
	var jar_path := FileUtilsScript.normalize(path)
	if not jar_path.to_lower().ends_with(".jar") or not jar_path.get_file().to_lower().contains("authlib"):
		ErrorReporter.report_error(ErrorInfoScript.make("AUTH_INJECTOR_REQUIRED", {"path": jar_path}))
		return
	_cfg.authlib_jar = jar_path
	_settings_panel.set_authlib_jar(jar_path)
	_settings_panel.set_login_status("已选择 authlib-injector.jar", "success")
	if _save_settings(true):
		LogManager.info("已选择 authlib-injector.jar：%s" % jar_path)


func _on_premium_login_requested() -> void:
	if _cfg == null or _selected.is_empty():
		_settings_panel.set_status("请先选择一个可用版本。", "warn")
		return
	if not _save_settings(true):
		return
	if _ms_auth.is_busy():
		_settings_panel.set_ms_status("已有正版登录请求正在进行", "warn")
		return
	_settings_panel.set_ms_busy(true)
	_settings_panel.clear_ms_code()
	_settings_panel.set_ms_status("正在向 Microsoft 申请设备码…", "info")
	var started: Dictionary = _ms_auth.start()
	if not bool(started.get("ok", false)):
		_settings_panel.set_ms_busy(false)
		_settings_panel.set_ms_status("登录未开始", "error")
		ErrorReporter.report_error(started.get("error", ErrorInfoScript.make("MS_LOGIN_FAILED", {"reason": "未知错误"})))
		return
	LogManager.info("开始正版 Microsoft 设备码登录")


func _on_ms_code_ready(user_code: String, verification_uri: String, _expires_in: int) -> void:
	_settings_panel.set_ms_code(user_code, verification_uri)
	_settings_panel.set_ms_status("验证码：%s。已尝试打开浏览器，请完成登录。" % user_code, "info")
	var uri := verification_uri.strip_edges()
	if uri.is_empty():
		uri = "https://www.microsoft.com/link"
	var err := OS.shell_open(uri)
	if err != OK:
		_settings_panel.set_ms_status("验证码：%s；请手动访问 %s" % [user_code, uri], "warn")


func _on_ms_login_finished(result: Variant) -> void:
	_settings_panel.set_ms_busy(false)
	var res: Dictionary = result if result is Dictionary else {"ok": false}
	if not bool(res.get("ok", false)):
		_settings_panel.set_ms_status("正版登录失败", "error")
		ErrorReporter.report_error(res.get("error", ErrorInfoScript.make("MS_LOGIN_FAILED", {"reason": "未知错误"})))
		return
	_settings_panel.clear_ms_code()
	var token_path := ConfigManager.auth_dir() + "/premium.json"
	var payload := {
		"accessToken": str(res.get("access_token", "")),
		"refreshToken": str(res.get("refresh_token", "")),
		"uuid": str(res.get("uuid", "")),
		"name": str(res.get("name", "")),
		"clientId": str(res.get("client_id", MicrosoftAuthScript.CLIENT_ID)),
	}
	var written := FileUtilsScript.write_text(token_path, JSON.stringify(payload, "\t") + "\n")
	if not bool(written.get("ok", false)):
		_settings_panel.set_ms_status("令牌保存失败", "error")
		ErrorReporter.report_error(ErrorInfoScript.make("MS_TOKEN_SAVE_FAILED", {
			"path": ProjectSettings.globalize_path(token_path).replace("\\", "/"),
			"reason": str(written.get("error", "")),
		}))
		return
	if _cfg == null:
		return
	_cfg.account_mode = "online"
	_cfg.username = str(res.get("name", _cfg.username))
	_settings_panel.set_account_mode("online")
	_settings_panel.set_username(str(_cfg.username))
	_settings_panel.set_ms_status("已登录：" + str(_cfg.username), "success")
	_save_settings(true)
	LogManager.info("正版 Microsoft 登录成功：%s" % str(_cfg.username))


func _on_thirdparty_login_requested() -> void:
	if _cfg == null or _selected.is_empty():
		_settings_panel.set_status("请先选择一个可用版本。", "warn")
		return
	if not _save_settings(true):
		return
	var password: String = _settings_panel.get_thirdparty_password()
	if password.is_empty():
		ErrorReporter.report_error(ErrorInfoScript.make("AUTH_PASSWORD_REQUIRED", {}))
		return
	var auth_url := str(_cfg.auth_url).strip_edges()
	if auth_url.is_empty():
		ErrorReporter.report_error(ErrorInfoScript.make("AUTH_SERVER_REQUIRED", {"path": ""}))
		return
	_settings_panel.set_login_busy(true)
	_settings_panel.set_login_status("正在连接认证服务器…", "info")
	var started: Dictionary = _online_auth.login(auth_url, str(_cfg.username), password)
	_settings_panel.clear_password()
	if not bool(started.get("ok", false)):
		_settings_panel.set_login_busy(false)
		_settings_panel.set_login_status("登录请求未发出", "error")
		ErrorReporter.report_error(started.get("error", ErrorInfoScript.make("AUTH_LOGIN_FAILED", {"reason": "未知错误"})))
		return
	LogManager.info("开始第三方 Yggdrasil 登录：%s" % auth_url)


func _on_thirdparty_login_finished(result: Variant) -> void:
	_settings_panel.set_login_busy(false)
	var res: Dictionary = result if result is Dictionary else {"ok": false}
	if not bool(res.get("ok", false)):
		_settings_panel.set_login_status("登录失败", "error")
		ErrorReporter.report_error(res.get("error", ErrorInfoScript.make("AUTH_LOGIN_FAILED", {"reason": "未知错误"})))
		return
	var token_path := AuthHelperScript.thirdparty_token_path()
	var payload := {
		"accessToken": str(res.get("access_token", "")),
		"clientToken": str(res.get("client_token", "")),
		"uuid": str(res.get("uuid", "")),
		"name": str(res.get("name", "")),
		"server": str(res.get("server", "")),
	}
	var written := FileUtilsScript.write_text(token_path, JSON.stringify(payload, "\t") + "\n")
	if not bool(written.get("ok", false)):
		ErrorReporter.report_error(ErrorInfoScript.make("AUTH_TOKEN_SAVE_FAILED", {
			"path": ProjectSettings.globalize_path(token_path).replace("\\", "/"),
			"reason": str(written.get("error", "")),
		}))
		return
	_cfg.account_mode = "thirdparty"
	_cfg.auth_url = str(res.get("server", _cfg.auth_url))
	_cfg.username = str(res.get("name", _cfg.username))
	if str(_cfg.authlib_jar).strip_edges().is_empty():
		_cfg.authlib_jar = AuthHelperScript.find_authlib_jar(_root)
		_settings_panel.set_authlib_jar(str(_cfg.authlib_jar))
	_settings_panel.set_account_mode("thirdparty")
	_settings_panel.set_username(str(_cfg.username))
	if str(_cfg.authlib_jar).strip_edges().is_empty():
		_settings_panel.set_login_status("已登录，但还需选择 authlib-injector.jar", "warn")
	else:
		_settings_panel.set_login_status("已登录：" + str(_cfg.username), "success")
	_save_settings(true)
	LogManager.info("第三方登录成功：%s（%s）" % [str(_cfg.username), str(_cfg.auth_url)])


func _schedule_autosave() -> void:
	if _cfg == null or _selected.is_empty() or _instance_dir.is_empty():
		return
	_autosave_timer.start()


func _on_autosave_timeout() -> void:
	if _cfg == null or _selected.is_empty() or _instance_dir.is_empty():
		return
	var user_edit = _settings_panel.get("_username")
	if user_edit is LineEdit and str(user_edit.text).strip_edges().is_empty():
		return
	_save_settings(true)


func _save_settings(from_launch: bool = false) -> bool:
	if _selected.is_empty() or not bool(_selected.get("usable", false)) or _cfg == null or _instance_dir.is_empty():
		if not from_launch:
			_settings_panel.set_status("请先选择一个可用版本。", "warn")
		return false
	_settings_panel.apply_to(_cfg)
	_cfg.version_id = str(_selected.get("id", ""))
	_cfg.source_root = _root
	_cfg.instance_dir = _instance_dir
	if str(_cfg.username).strip_edges().is_empty():
		ErrorReporter.report_error(ErrorInfoScript.make("ACCOUNT_INVALID", {"reason": "用户名不能为空"}))
		return false
	InstanceConfigScript.ensure_game_dirs(_instance_dir)
	var saved: Dictionary = _cfg.save_to(_instance_dir)
	if not bool(saved.get("ok", false)):
		var save_err := ErrorInfoScript.make("INSTANCE_SAVE_FAILED", {
			"path": _display_path(str(saved.get("path", _instance_dir + "/" + InstanceConfigScript.VERSION_CONFIG_NAME))),
			"reason": str(saved.get("reason", "未知")),
		})
		ErrorReporter.report_error(save_err)
		return false
	ConfigManager.last_version = str(_selected.get("id", ""))
	ConfigManager.last_instance = str(_cfg.version_id)
	ConfigManager.game_root = _root
	ConfigManager.last_root = _root
	ConfigManager.last_username = str(_cfg.username)
	ConfigManager.java_mode = str(_cfg.java_mode)
	ConfigManager.java_path = str(_cfg.java_path)
	ConfigManager.max_memory_mb = int(_cfg.max_memory_mb)
	var global_err := ConfigManager.save_config()
	if global_err != OK:
		LogManager.warn("全局配置保存失败：%s" % error_string(global_err))
	LogManager.info("版本设置已保存：%s（%s）" % [str(_cfg.version_id), _display_path(_instance_dir)])
	if not from_launch:
		_settings_panel.set_status("设置已保存到版本目录：%s" % _display_path(_instance_dir), "success")
	return true


func _launch() -> void:
	if _running:
		ErrorReporter.report_error(ErrorInfoScript.make("LAUNCH_BUSY", {}))
		return
	if _busy:
		_settings_panel.set_status("正在执行其他任务，请稍候。", "warn")
		return
	if _selected.is_empty() or not bool(_selected.get("usable", false)):
		ErrorReporter.report_error(ErrorInfoScript.make("VERSION_UNUSABLE", {
			"name": str(_selected.get("id", "")),
			"reason": "未选择可用版本",
			"path": _display_path(_root),
		}))
		return
	if not _save_settings(true):
		return
	var snapshot = InstanceConfigScript.from_dict(_cfg.to_dict(), _instance_dir)
	var version_id := str(_selected.get("id", ""))
	var root := _display_path(_root)
	var inst := _display_path(_instance_dir)
	_busy = true
	_settings_panel.set_busy(true)
	_settings_panel.set_progress(5, "正在检查 Java、运行库与资源…")
	LogManager.info("开始准备启动：版本 %s，版本目录 %s" % [version_id, inst])
	var task = ThreadTaskScript.new()
	add_child(task)
	_launch_task = task
	task.finished.connect(_on_launch_built)
	task.start(func() -> Dictionary:
		return LaunchBuilderScript.build(version_id, root, inst, snapshot)
	)


func _on_launch_built(result: Variant) -> void:
	_launch_task = null
	var res: Dictionary = result if result is Dictionary else {"ok": false}
	if not bool(res.get("ok", false)):
		_busy = false
		_settings_panel.set_busy(false)
		_settings_panel.set_progress(0)
		_settings_panel.play_launch_failure()
		ErrorReporter.report_error(res.get("error", ErrorInfoScript.make("LAUNCH_FAILED", {"path": "", "reason": "启动准备失败"})))
		return
	var warnings: Array = res.get("warnings", [])
	for i in range(mini(12, warnings.size())):
		LogManager.warn("启动警告：" + str(warnings[i]))
	if warnings.size() > 12:
		LogManager.warn("启动警告较多，已省略 %d 条" % (warnings.size() - 12))
	_settings_panel.set_progress(75, "正在启动游戏进程…")
	var game_log_path := LogManager.game_log_path(str(_root.get_file()) + "__" + str(_cfg.version_id))
	var start_result: Dictionary = _process_runner.start(
		str(res.get("java_path", "")),
		res.get("argv", PackedStringArray()),
		game_log_path,
		str(res.get("command_preview", ""))
	)
	if not bool(start_result.get("ok", false)):
		_busy = false
		_settings_panel.set_busy(false)
		_settings_panel.set_progress(0)
		_settings_panel.play_launch_failure()
		ErrorReporter.report_error(start_result.get("error", ErrorInfoScript.make("LAUNCH_FAILED", {"path": "", "reason": "进程启动失败"})))
		return
	_running = true
	_busy = false
	_settings_panel.set_running(true)
	_settings_panel.set_busy(false)
	_settings_panel.set_progress(100)
	_settings_panel.play_launch_success()
	var pid := int(start_result.get("pid", -1))
	var log_path := _display_path(str(start_result.get("log_path", "")))
	_settings_panel.set_status("游戏运行中（PID %d）" % pid, "success")
	_settings_panel.set_status_tooltip("游戏日志：" + log_path)
	LogManager.info("启动完成：PID=%d，日志=%s" % [pid, log_path])
	_cfg.last_launch = Time.get_datetime_string_from_system(true)
	_cfg.save_to(_instance_dir)
	ConfigManager.last_instance = str(_cfg.version_id)
	ConfigManager.last_version = str(_selected.get("id", ""))
	ConfigManager.last_root = _root
	ConfigManager.save_config()


func _on_process_finished(result: Dictionary) -> void:
	_running = false
	_settings_panel.set_running(false)
	_settings_panel.set_progress(0)
	var log_path := _display_path(str(result.get("log_path", "")))
	_settings_panel.set_status("游戏已结束，日志见启动器目录 logs/instances/", "info")
	_settings_panel.set_status_tooltip("游戏日志：" + log_path)
	LogManager.info("游戏进程已结束，日志：%s" % log_path)


func _display_path(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path).replace("\\", "/")
	return path


func _pick_resource_files(kind: String) -> void:
	if _cfg == null or _selected.is_empty():
		_settings_panel.set_status("请先选择一个可用版本。", "warn")
		return
	if not _save_settings(true):
		return
	var title := "选择 Mod 文件（可多选）"
	var filters := PackedStringArray(["*.jar ; Mod 文件", "* ; 所有文件"])
	if kind == "shader":
		title = "选择光影包（.zip，可多选）"
		filters = PackedStringArray(["*.zip ; 光影包", "* ; 所有文件"])
	elif kind == "resource":
		title = "选择材质包（.zip，可多选）"
		filters = PackedStringArray(["*.zip ; 材质包", "* ; 所有文件"])
	_dialogs.pick_files(kind, title, filters, true, _display_path(_cfg.effective_game_dir(_root)))


func _install_resources(kind: String, paths: PackedStringArray) -> void:
	if _cfg == null:
		return
	_busy = true
	_settings_panel.set_busy(true)
	_settings_panel.set_progress(0, "正在安装 %s…" % ResourceInstallerScript.label_for(kind))
	var target: String = _cfg.effective_game_dir(_root)
	LogManager.info("开始安装 %s：%d 个文件 -> %s" % [ResourceInstallerScript.label_for(kind), paths.size(), _display_path(target)])
	var started: bool = _installer.install_async(paths, kind, target)
	if not started:
		_busy = false
		_settings_panel.set_busy(false)
		_settings_panel.set_status("已有安装任务在进行。", "warn")


func _on_install_progress(percent: int, message: String) -> void:
	_settings_panel.set_progress(percent, message)


func _on_resources_finished(result: Variant) -> void:
	_busy = false
	_settings_panel.set_busy(false)
	var res: Dictionary = result if result is Dictionary else {"ok": false, "errors": ["未知错误"]}
	var copied: Array = res.get("copied", [])
	var unchanged: Array = res.get("unchanged", [])
	var backups: Array = res.get("backups", [])
	var errors: Array = res.get("errors", [])
	var target := str(res.get("target_dir", ""))
	var lines: Array[String] = []
	lines.append("复制成功：%d 个文件" % copied.size())
	lines.append("已存在跳过：%d 个文件" % unchanged.size())
	lines.append("目标目录：%s" % _display_path(target))
	if not backups.is_empty():
		lines.append("")
		lines.append("已备份 %d 个同名文件：" % backups.size())
		for i in range(mini(10, backups.size())):
			lines.append("  " + str(backups[i]))
	if not errors.is_empty():
		lines.append("")
		lines.append("错误 %d 个：" % errors.size())
		for i in range(mini(10, errors.size())):
			lines.append("  " + str(errors[i]))
		if errors.size() > 10:
			lines.append("  ……另有 %d 个错误，请查看日志" % (errors.size() - 10))
	var text := "\n".join(lines)
	_dialogs.show_report("安装完成" if errors.is_empty() else "安装完成，但有错误", text, text)
	if errors.is_empty():
		_settings_panel.set_status("已复制 %d 个文件到 %s" % [copied.size(), target], "success")
		LogManager.info("资源安装完成：%d 个文件" % copied.size())
	else:
		_settings_panel.set_status("安装完成，但有 %d 个错误，请查看报告。" % errors.size(), "warn")
		LogManager.error("资源安装出现 %d 个错误" % errors.size())


func _on_import_mrpack_requested() -> void:
	if _selected.is_empty() or _cfg == null:
		_settings_panel.set_status("请先选择一个可用版本。", "warn")
		return
	if not _save_settings(true):
		return
	_dialogs.pick_files("mrpack", "选择整合包文件（.mrpack）", PackedStringArray(["*.mrpack ; Modrinth 整合包", "* ; 所有文件"]), false, _display_path(_root))


func _show_mrpack_target() -> void:
	# 实例已经自动跟随版本，不需要再选目标实例；直接选本地资源来源目录。
	_dialogs.pick_dir("mrpack_source", "选择整合包本地资源来源目录（可取消）", _display_path(_instance_dir))


func _run_mrpack_import(instance_dir: String, source_dir: String) -> void:
	if _pending_mrpack.is_empty() or not FileAccess.file_exists(_pending_mrpack):
		_settings_panel.set_status("整合包文件不存在。", "error")
		return
	if _cfg == null:
		return
	var target_game_dir: String = _cfg.effective_game_dir(_root)
	InstanceConfigScript.ensure_game_dirs(target_game_dir)
	FileUtilsScript.ensure_dir(target_game_dir)
	_busy = true
	_settings_panel.set_busy(true)
	_settings_panel.set_progress(0, "正在导入整合包…")
	LogManager.info("开始导入整合包：%s -> %s（来源目录：%s）" % [_pending_mrpack, _display_path(target_game_dir), source_dir if not source_dir.is_empty() else "未指定"])
	var started: bool = _importer.import_async(_pending_mrpack, target_game_dir, source_dir)
	if not started:
		_busy = false
		_settings_panel.set_busy(false)


func _on_mrpack_finished(result: Variant) -> void:
	_busy = false
	_settings_panel.set_busy(false)
	var res: Dictionary = result if result is Dictionary else {"ok": false}
	if not bool(res.get("ok", false)):
		_settings_panel.set_status("整合包导入失败。", "error")
		ErrorReporter.report_error(res.get("error", ErrorInfoScript.make("MRPACK_IMPORT_FAILED", {"reason": "未知错误"})))
		return
	var copied: Array = res.get("copied", [])
	var unchanged: Array = res.get("unchanged", [])
	var backups: Array = res.get("backups", [])
	var missing: Array = res.get("missing", [])
	var errors: Array = res.get("errors", [])
	var warnings: Array = res.get("warnings", [])
	var lines: Array[String] = [
		"整合包：%s" % str(res.get("name", "")),
		"目标目录：%s" % _display_path(str(res.get("target_dir", ""))),
		"",
		"复制文件：%d 个" % copied.size(),
		"已存在跳过：%d 个" % unchanged.size(),
		"备份文件：%d 个" % backups.size(),
		"缺失文件：%d 个" % missing.size(),
		"错误：%d 个" % errors.size(),
		"警告：%d 个" % warnings.size(),
	]
	if not missing.is_empty():
		lines.append("")
		lines.append("以下文件需你自行获取（本启动器不联网下载）：")
		for i in range(mini(20, missing.size())):
			var item: Dictionary = missing[i]
			lines.append("  " + str(item.get("path", "")) + "（" + str(item.get("reason", "")) + "）")
		if missing.size() > 20:
			lines.append("  ……另有 %d 个缺失文件" % (missing.size() - 20))
	if not errors.is_empty():
		lines.append("")
		lines.append("错误详情：")
		for i in range(mini(10, errors.size())):
			lines.append("  " + str(errors[i]))
	if not warnings.is_empty():
		lines.append("")
		lines.append("警告：")
		for i in range(mini(10, warnings.size())):
			lines.append("  " + str(warnings[i]))
	var text := "\n".join(lines)
	_dialogs.show_report("整合包导入结果", text, text)
	var target := str(res.get("target_dir", ""))
	_settings_panel.set_status("整合包导入完成：复制 %d 个，缺失 %d 个。" % [copied.size(), missing.size()], "success" if missing.is_empty() and errors.is_empty() else "warn")
	LogManager.info("整合包导入完成：复制 %d，缺失 %d，错误 %d，目标 %s" % [copied.size(), missing.size(), errors.size(), target])


func _open_instance_dir() -> void:
	if _cfg == null or _instance_dir.is_empty():
		_settings_panel.set_status("请先选择一个可用版本。", "warn")
		return
	var game_dir: String = _cfg.effective_game_dir(_root)
	InstanceConfigScript.ensure_game_dirs(game_dir)
	var global_dir := ProjectSettings.globalize_path(game_dir).replace("\\", "/")
	var err := OS.shell_open(global_dir)
	if err != OK:
		LogManager.error("无法打开游戏目录：%s（%s）" % [global_dir, error_string(err)])


func _on_error_raised(err: Dictionary) -> void:
	if _dialogs != null:
		_dialogs.show_error(err)
