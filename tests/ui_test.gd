extends Control
## 界面联动测试：实例化真实主界面，验证扫描、选择、保存、重命名、资源复制与启动失败提示。
## 运行：godot --headless --path . tests/ui_test.tscn

const FileUtilsScript = preload("res://scripts/core/file_utils.gd")
const InstanceConfigScript = preload("res://scripts/core/instance_config.gd")
const AuthHelperScript = preload("res://scripts/core/auth_helper.gd")
const MainScene = preload("res://main.tscn")

var _failures: Array[String] = []
var _main
var _game_root := "user://ui_test_game"
var _second_root := "user://ui_test_game2"


func _ready() -> void:
	var suffix := str(Time.get_ticks_usec())
	ConfigManager.instances_root = "user://ui_test_instances_" + suffix
	ConfigManager.auth_root = "user://ui_test_auth_" + suffix
	ConfigManager.config_path = "user://ui_test_launcher_" + suffix + ".cfg"
	ConfigManager.java_mode = "auto"
	ConfigManager.java_path = ""
	ConfigManager.last_username = "Player"
	ConfigManager.max_memory_mb = 2048
	OS.set_environment("PATH", "")
	_prepare_fixture()
	_prepare_second_root()
	ConfigManager.set_game_root(_game_root)
	ConfigManager.last_version = ""
	ConfigManager.save_config()

	_main = MainScene.instantiate()
	add_child(_main)
	await _wait_until(func() -> bool:
		return _main.get("_scan_task") == null and (_main.get("_versions") as Array).size() > 0
	, 8.0)

	var versions: Array = _main.get("_versions")
	_check("界面扫描到版本", versions.size() == 2, str(versions.size()))
	_check("可用版本计数", VersionScanner_count(versions) == 1)
	var vp = _main.get("_version_panel")
	_check("版本树条目", int((vp.get("_entries") as Array).size()) == 2, str((vp.get("_entries") as Array).size()))
	_check("版本树按文件夹分组", int((vp.get("_root_items") as Dictionary).size()) == 1)
	var second_item: TreeItem = (vp.get("_version_items") as Dictionary).get(_game_root + "|bad", null)
	_check("版本名使用文件夹名", second_item != null and second_item.get_text(0) == "bad")
	_check("版本组件计数", second_item != null)
	var demo_item: TreeItem = (vp.get("_version_items") as Dictionary).get(_game_root + "|demo", null)
	_check("版本树 Mod 计数", demo_item != null and demo_item.get_text(1) == "1", demo_item.get_text(1) if demo_item != null else "")
	_check("版本树光影计数", demo_item != null and demo_item.get_text(2) == "1")
	_check("版本树存档计数", demo_item != null and demo_item.get_text(4) == "1")
	_check("原生文件选择框", bool(_main.get("_dialogs").get("_file_dialog").use_native_dialog))
	_check("原生文件夹选择框", bool(_main.get("_dialogs").get("_dir_dialog").use_native_dialog))
	_check("原生来源目录选择框", bool(_main.get("_dialogs").get("_source_dir_dialog").use_native_dialog))
	_check("自动选中可用版本", str((_main.get("_selected") as Dictionary).get("id", "")) == "demo")
	_check("实例配置已创建", _main.get("_cfg") != null)
	_check("实例目录为版本目录", str(_main.get("_instance_dir")) == _game_root + "/versions/demo", str(_main.get("_instance_dir")))
	_check("旧实例设置已迁移", str(_main.get("_cfg").username) == "MigratedUser" and int(_main.get("_cfg").max_memory_mb) == 4096, str(_main.get("_cfg").username) + "/" + str(_main.get("_cfg").max_memory_mb))
	_check("默认使用版本文件夹", str(_main.get("_cfg").game_dir_mode) == "version")

	var bb = _main.get("_bottom_bar")
	var bottom_buttons: Array[String] = []
	for child in bb.get_children():
		if child is Button:
			bottom_buttons.append(str(child.text))
	_check("底部按钮", bottom_buttons == ["说明书", "免责声明", "下载器链接"], str(bottom_buttons))
	_check("说明书弹窗存在", bb.get("_manual_dialog") != null)
	_check("免责声明弹窗存在", bb.get("_disclaimer_dialog") != null)
	var bottom_button_nodes: Array[Button] = []
	for child in bb.get_children():
		if child is Button:
			bottom_button_nodes.append(child)
	_check("下载器链接按钮地址", str(bottom_button_nodes[2].tooltip_text) == "https://github.com/glgl6688/gl-MC-downloader/", str(bottom_button_nodes[2].tooltip_text))
	bottom_button_nodes[0].pressed.emit()
	await get_tree().process_frame
	_check("说明书按钮弹出窗口", bool(bb.get("_manual_dialog").visible))
	bb.get("_manual_dialog").hide()

	_main.call("_on_dir_picked", "game_root", _second_root)
	await _wait_until(func() -> bool:
		return _main.get("_scan_task") == null and (_main.get("_versions") as Array).size() == 3
	, 8.0)
	_check("添加第二个游戏文件夹", (_main.get("_versions") as Array).size() == 3, str((_main.get("_versions") as Array).size()))
	_check("版本树出现两个根节点", int((vp.get("_root_items") as Dictionary).size()) == 2)
	var root_a: TreeItem = (vp.get("_root_items") as Dictionary).get(_game_root, null)
	var root_b: TreeItem = (vp.get("_root_items") as Dictionary).get(_second_root, null)
	_check("根节点是同级而非嵌套", root_a != null and root_b != null and root_a.get_parent() == root_b.get_parent())
	_check("版本按根节点分组", root_a != null and root_b != null and root_a.get_child_count() == 2 and root_b.get_child_count() == 1)
	_check("第二文件夹版本存在", str((_main.get("_versions") as Array)[2].get("id", "")) == "second")
	vp.call("select_version", "demo", _game_root)
	await get_tree().process_frame
	var confirm_dlg = _main.get("_dialogs").get("_confirm_dialog")
	_main.call("_remove_current_root")
	await get_tree().process_frame
	_check("移除文件夹需要确认", bool(confirm_dlg.visible))
	confirm_dlg.hide()
	_check("取消确认不删除文件夹", (_main.get("_roots") as Array).size() == 2)
	_check("顶部路径已移除", _main.get("_root_edit") == null)
	_check("顶部保留移除按钮", str(_main.get("_remove_root_btn").text) == "移除当前文件夹")
	root_a.select(0)
	await get_tree().process_frame
	_check("选择根文件夹显示路径", vp.get("_root_path_row").visible and str(vp.get("_root_path").text) == _game_root, str(vp.get("_root_path").text))
	vp.call("select_version", "demo", _game_root)
	await get_tree().process_frame

	await _wait_until(func() -> bool:
		return _main.get("_java_task") == null and not (_main.get("_java_result") as Dictionary).is_empty()
	, 10.0)
	var java_res: Dictionary = _main.get("_java_result")
	var java_usable := bool(java_res.get("ok", false)) and bool(java_res.get("meets_requirement", true))
	_check("无可用 Java 时检测为错误", not java_usable, str(java_res))
	var sp = _main.get("_settings_panel")
	_check("日志位于启动器目录", not str(LogManager.logs_root).begins_with("user://") and str(LogManager.logs_root).ends_with("/logs"), str(LogManager.logs_root))
	sp.call("set_account_mode", "online")
	await get_tree().process_frame
	_check("正版模式显示登录按钮", sp.get("_ms_login_btn").visible)
	_check("验证码行常显", sp.get("_ms_code_row").visible)
	_check("正版模式不显示 client_id 输入", sp.get("_ms_client_row") == null or not sp.get("_ms_client_row").visible)
	_check("正版模式隐藏第三方密码", not sp.get("_password_row").visible)
	sp.call("set_ms_code", "ABCD-EFGH", "https://www.microsoft.com/link")
	_check("正版验证码显示", sp.get("_ms_code").text == "ABCD-EFGH" and sp.get("_ms_code_row").visible)
	_check("复制验证码按钮已启用", not sp.get("_ms_copy_btn").disabled)
	_check("打开登录页按钮已启用", not sp.get("_ms_open_btn").disabled)
	sp.call("clear_ms_code")
	sp.call("set_account_mode", "offline")
	await get_tree().process_frame
	_check("Java 状态可读", sp.get("_java_status").text.length() > 0)
	_check("Java 帮助按钮出现", sp.get("_java_help").visible)

	var saved: bool = _main.call("_save_settings", true)
	_check("保存实例设置", saved)
	var inst_dir := str(_main.get("_instance_dir"))
	var cfg_path := inst_dir + "/gl-instance.json"
	_check("gl-instance.json 已写入", FileAccess.file_exists(cfg_path), cfg_path)
	var loaded := InstanceConfigScript.load_file(cfg_path)
	_check("保存的版本 id 正确", bool(loaded.get("ok", false)) and str(loaded.get("config").version_id) == "demo")
	var conf := ConfigFile.new()
	conf.load(ConfigManager.config_path)
	var stored_roots: PackedStringArray = conf.get_value("launcher", "game_roots", PackedStringArray())
	_check("多文件夹配置持久化", stored_roots.size() == 2, str(stored_roots))

	sp.get("_memory").value = 3072
	await get_tree().create_timer(0.8).timeout
	var reloaded := InstanceConfigScript.load_for_version(inst_dir, "demo", _game_root)
	_check("修改设置自动保存", bool(reloaded.get("found", false)) and int(reloaded.get("config").max_memory_mb) == 3072, str(reloaded))
	_check("设置摘要显示组件", sp.get("_component_summary").text.contains("Mod 1") and sp.get("_component_summary").text.contains("光影 1"), sp.get("_component_summary").text)

	_main.call("_on_manage_components_requested")
	await get_tree().process_frame
	var dlg = _main.get("_dialogs")
	_check("组件管理弹窗", dlg.get("_components_dialog").visible)
	_check("组件列表可选择", (dlg.get("_components_checks") as Array).size() >= 3, str((dlg.get("_components_checks") as Array).size()))
	dlg.get("_components_dialog").hide()
	_main.call("_on_components_confirmed", PackedStringArray([_game_root + "/versions/demo/mods/ui-test-mod.jar"]))
	await _wait_until(func() -> bool:
		return not FileAccess.file_exists(_game_root + "/versions/demo/mods/ui-test-mod.jar")
	, 5.0)
	_check("组件移出版本目录", not FileAccess.file_exists(_game_root + "/versions/demo/mods/ui-test-mod.jar"))
	_check("组件移到备份目录", str(dlg.get("_report_body").text).contains("gl-component-backup") and str(dlg.get("_report_body").text).contains("备份位置"), str(dlg.get("_report_body").text))
	await _wait_until(func() -> bool: return _main.get("_scan_task") == null, 5.0)

	vp.call("select_version", "bad")
	await get_tree().process_frame
	_check("不可用版本被选中", str((_main.get("_selected") as Dictionary).get("id", "")) == "bad")
	_check("不可用版本禁用启动", sp.get("_launch_btn").disabled)
	_check("不可用版本提供复制路径", vp.get("_reason_row").visible and vp.get("_reason_copy").visible)
	vp.call("select_version", "demo")
	await get_tree().process_frame
	_check("重新选回可用版本", _main.get("_cfg") != null)

	var mod_src := FileUtilsScript.normalize(OS.get_environment("TEMP")) + "/ui_mod_%d.jar" % Time.get_ticks_usec()
	FileUtilsScript.write_bytes(mod_src, "MOD".to_utf8_buffer())
	var target := str(_main.get("_cfg").effective_game_dir(str(_main.get("_root"))))
	_main.call("_install_resources", "mod", PackedStringArray([mod_src]))
	var installed := await _wait_until(func() -> bool:
		return FileAccess.file_exists(target + "/mods/" + mod_src.get_file())
	, 8.0)
	_check("界面资源复制完成", installed, target + "/mods")
	await _wait_until(func() -> bool: return not bool(_main.get("_busy")), 5.0)

	var pack_path := FileUtilsScript.normalize(OS.get_environment("TEMP")) + "/ui_pack_%d.mrpack" % Time.get_ticks_usec()
	_write_mrpack(pack_path)
	_main.set("_pending_mrpack", pack_path)
	_main.call("_run_mrpack_import", str(_main.get("_instance_dir")), "")
	var pack_imported := await _wait_until(func() -> bool:
		return FileAccess.file_exists(target + "/config/from_pack.txt")
	, 8.0)
	_check("整合包界面导入完成", pack_imported, target + "/config")
	await _wait_until(func() -> bool: return not bool(_main.get("_busy")), 5.0)

	var launch_ok := true
	if _main.get("_cfg") == null:
		launch_ok = false
	_check("启动前配置存在", launch_ok)
	_main.call("_launch")
	var error_shown := await _wait_until(func() -> bool:
		var dlg2 = _main.get("_dialogs")
		return dlg2.get("_error_dialog").visible and not bool(_main.get("_busy"))
	, 12.0)
	_check("缺少 Java 时弹出错误框", error_shown)
	var err: Dictionary = _main.get("_dialogs").get("_error_current")
	_check("错误框包含路径与建议", not str(err.get("path", "")).is_empty() or not str(err.get("fix_hint", "")).is_empty())
	_check("错误码可读", str(err.get("code", "")) in ["JAVA_NOT_FOUND", "JAVA_NOT_RUNNABLE", "JAVA_VERSION_UNKNOWN", "JAVA_TOO_OLD"], str(err.get("code", "")))
	_check("未误启动进程", not bool(_main.get("_running")))

	_main.call("_on_ms_login_finished", {
		"ok": true,
		"access_token": "MS-MOCK-TOKEN",
		"refresh_token": "MS-REFRESH",
		"uuid": "99999999-8888-7777-6666-555555555555",
		"name": "MSPlayer",
		"client_id": "test-client-id",
	})
	await get_tree().process_frame
	var premium_path := ConfigManager.auth_dir() + "/premium.json"
	_check("正版令牌写入", FileAccess.file_exists(premium_path), premium_path)
	var premium_cfg = _main.get("_cfg")
	_check("正版用户名回填", premium_cfg != null and str(premium_cfg.username) == "MSPlayer")
	_check("正版模式已切换", premium_cfg != null and str(premium_cfg.account_mode) == "online")
	var resolved = AuthHelperScript.resolve(premium_cfg)
	_check("正版令牌可解析", bool(resolved.get("ok", false)) and str(resolved.get("user_type", "")) == "msa" and str(resolved.get("access_token", "")) == "MS-MOCK-TOKEN", str(resolved))

	await get_tree().create_timer(0.2).timeout
	_cleanup()
	print("")
	if _failures.is_empty():
		print("界面测试全部通过")
		get_tree().quit(0)
	else:
		print("界面测试失败 %d 项：" % _failures.size())
		for item in _failures:
			print("  - ", item)
		get_tree().quit(1)


func VersionScanner_count(versions: Array) -> int:
	var count := 0
	for v in versions:
		if bool(v.get("usable", false)):
			count += 1
	return count


func _prepare_fixture() -> void:
	_rm_rf(_game_root)
	_rm_rf(ConfigManager.instances_dir())
	_rm_rf(ConfigManager.auth_dir())
	FileUtilsScript.ensure_dir(ConfigManager.instances_dir())
	FileUtilsScript.ensure_dir(ConfigManager.auth_dir())
	FileUtilsScript.write_text(_game_root + "/versions/demo/demo.json", JSON.stringify({
		"id": "demo", "type": "release", "mainClass": "demo.Main",
		"javaVersion": {"majorVersion": 99},
	}))
	FileUtilsScript.write_bytes(_game_root + "/versions/demo/demo.jar", PackedByteArray([1, 2, 3]))
	FileUtilsScript.ensure_dir(_game_root + "/versions/demo/mods")
	FileUtilsScript.write_bytes(_game_root + "/versions/demo/mods/ui-test-mod.jar", "MOD".to_utf8_buffer())
	FileUtilsScript.ensure_dir(_game_root + "/versions/demo/shaderpacks")
	FileUtilsScript.write_bytes(_game_root + "/versions/demo/shaderpacks/ui-test-shader.zip", "SHADER".to_utf8_buffer())
	FileUtilsScript.ensure_dir(_game_root + "/versions/demo/saves/ui-test-world")
	FileUtilsScript.write_bytes(_game_root + "/versions/demo/saves/ui-test-world/level.dat", "WORLD".to_utf8_buffer())
	FileUtilsScript.write_text(_game_root + "/versions/bad/bad.json", JSON.stringify({"id": "bad", "mainClass": "bad.Main"}))
	FileUtilsScript.ensure_dir(_game_root + "/assets")
	# 模拟旧版本 user://instances 配置，验证迁移后不会重置设置。
	var old_dir := InstanceConfigScript.default_instance_dir(ConfigManager.instances_dir(), "demo")
	FileUtilsScript.ensure_dir(old_dir)
	var old_cfg = InstanceConfigScript.create("demo", "demo")
	old_cfg.username = "MigratedUser"
	old_cfg.max_memory_mb = 4096
	old_cfg.instance_dir = old_dir
	old_cfg.save()


func _prepare_second_root() -> void:
	_rm_rf(_second_root)
	FileUtilsScript.write_text(_second_root + "/versions/second/second.json", JSON.stringify({
		"id": "second", "type": "release", "mainClass": "second.Main",
		"javaVersion": {"majorVersion": 99},
	}))
	FileUtilsScript.write_bytes(_second_root + "/versions/second/second.jar", PackedByteArray([1]))


func _write_mrpack(path: String) -> void:
	var packer := ZIPPacker.new()
	var err := packer.open(path)
	if err != OK:
		_failures.append("无法创建测试整合包")
		return
	var index := {
		"formatVersion": 1,
		"name": "UI Test Pack",
		"versionId": "1.0.0",
		"dependencies": {"minecraft": "demo"},
		"files": [],
	}
	packer.start_file("modrinth.index.json")
	packer.write_file(JSON.stringify(index).to_utf8_buffer())
	packer.close_file()
	packer.start_file("overrides/config/from_pack.txt")
	packer.write_file("PACK".to_utf8_buffer())
	packer.close_file()
	packer.close()


func _rm_rf(path: String) -> void:
	var p := FileUtilsScript.normalize(path)
	if not DirAccess.dir_exists_absolute(p):
		return
	var dir := DirAccess.open(p)
	if dir != null:
		for f in dir.get_files():
			DirAccess.remove_absolute(p + "/" + str(f))
		for sub in dir.get_directories():
			_rm_rf(p + "/" + str(sub))
	DirAccess.remove_absolute(p)


func _cleanup() -> void:
	_rm_rf(ConfigManager.instances_dir())
	_rm_rf(ConfigManager.auth_dir())
	_rm_rf(_game_root)
	_rm_rf(_second_root)
	if FileAccess.file_exists(ConfigManager.config_path):
		DirAccess.remove_absolute(ConfigManager.config_path)


func _wait_until(predicate: Callable, timeout_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await get_tree().process_frame
	return bool(predicate.call())


func _check(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("PASS  ", name)
	else:
		_failures.append(name + ("" if detail.is_empty() else " :: " + detail.substr(0, 300)))
		print("FAIL  ", name, "  ", detail.substr(0, 200))
