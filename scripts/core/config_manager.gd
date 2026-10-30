extends Node
## 全局配置：<启动器目录>/launcher.cfg
## 只保存启动器自身的设置，不修改游戏文件。

const INSTANCES_DIR := "user://instances"
const AUTH_DIR := "user://auth"
const CACHE_DIR := "user://cache"
const RuntimePathsScript = preload("res://scripts/core/runtime_paths.gd")
const FileUtilsScript = preload("res://scripts/core/file_utils.gd")

var game_root := ""
var game_roots: Array[String] = []
var last_root := ""
var last_version := ""
var last_instance := ""
var last_username := "Player"
var java_mode := "auto"
var java_path := ""
var max_memory_mb := 2048
var reduce_motion := false
var low_spec := false
var config_load_error := ""

## 测试可重定向；正常运行时为空，由 RuntimePaths 选择启动器目录。
var instances_root := INSTANCES_DIR
var auth_root := ""
var cache_root := ""
var config_path := ""


func _ready() -> void:
	_apply_default_paths()
	_migrate_legacy_config()
	_migrate_legacy_auth()
	_ensure_base_dirs()
	load_config()


func _apply_default_paths() -> void:
	if config_path.is_empty():
		config_path = RuntimePathsScript.path("launcher.cfg")
	if auth_root.is_empty():
		auth_root = RuntimePathsScript.path("auth")
	if cache_root.is_empty():
		cache_root = RuntimePathsScript.path("cache")


func _ensure_base_dirs() -> void:
	for p in [auth_root, cache_root]:
		if not str(p).is_empty():
			DirAccess.make_dir_recursive_absolute(p)


func instances_dir() -> String:
	return instances_root


func auth_dir() -> String:
	return auth_root


func cache_dir() -> String:
	return cache_root


func launcher_data_dir() -> String:
	return RuntimePathsScript.data_dir()


func _migrate_legacy_config() -> void:
	if FileAccess.file_exists(config_path):
		return
	var legacy := RuntimePathsScript.legacy_user_path("launcher.cfg")
	if FileAccess.file_exists(legacy):
		var f := FileAccess.open(legacy, FileAccess.READ)
		if f != null:
			var text := f.get_as_text()
			f.close()
			var written := FileUtilsScript.write_text(config_path, text)
			if bool(written.get("ok", false)):
				printerr("[ConfigManager] 已把启动器配置迁移到：%s" % config_path)


func _migrate_legacy_auth() -> void:
	if str(auth_root).is_empty():
		return
	var legacy := RuntimePathsScript.legacy_user_path("auth")
	if not DirAccess.dir_exists_absolute(legacy):
		return
	DirAccess.make_dir_recursive_absolute(auth_root)
	for name in ["premium.json", "thirdparty.json"]:
		var old_file: String = legacy + "/" + str(name)
		var new_file: String = auth_root + "/" + str(name)
		if FileAccess.file_exists(old_file) and not FileAccess.file_exists(new_file):
			var f := FileAccess.open(old_file, FileAccess.READ)
			if f != null:
				var text := f.get_as_text()
				f.close()
				FileUtilsScript.write_text(new_file, text)


func global_path(path: String) -> String:
	var p := str(path).replace("\\", "/")
	if p.begins_with("user://") or p.begins_with("res://"):
		return ProjectSettings.globalize_path(p).replace("\\", "/")
	return p


func load_config() -> void:
	var cfg := ConfigFile.new()
	if not FileAccess.file_exists(config_path):
		game_root = _guess_game_root()
		game_roots.clear()
		game_roots.append(game_root)
		save_config()
		return
	var err := cfg.load(config_path)
	if err != OK:
		config_load_error = "无法读取 launcher.cfg：%s" % error_string(err)
		game_root = _guess_game_root()
		game_roots.clear()
		game_roots.append(game_root)
		return
	game_root = str(cfg.get_value("launcher", "game_root", "")).replace("\\", "/")
	last_root = str(cfg.get_value("launcher", "last_root", "")).replace("\\", "/")
	last_version = str(cfg.get_value("launcher", "last_version", ""))
	last_instance = str(cfg.get_value("launcher", "last_instance", ""))
	last_username = str(cfg.get_value("launcher", "last_username", "Player"))
	max_memory_mb = int(cfg.get_value("launcher", "max_memory_mb", 2048))
	java_mode = str(cfg.get_value("java", "mode", "auto"))
	java_path = str(cfg.get_value("java", "path", "")).replace("\\", "/")
	reduce_motion = bool(cfg.get_value("ui", "reduce_motion", false))
	low_spec = bool(cfg.get_value("ui", "low_spec", false))
	if java_mode != "manual":
		java_mode = "auto"
	max_memory_mb = clampi(max_memory_mb, 512, 32768)

	game_roots.clear()
	var raw_roots: Variant = cfg.get_value("launcher", "game_roots", PackedStringArray())
	if raw_roots is Array or raw_roots is PackedStringArray:
		for item in raw_roots:
			var p := _normalize_root(str(item))
			if not p.is_empty() and not game_roots.has(p):
				game_roots.append(p)
	if game_roots.is_empty() and not game_root.is_empty():
		game_roots.clear()
		game_roots.append(_normalize_root(game_root))
	if game_roots.is_empty():
		game_root = _guess_game_root()
		game_roots.clear()
		game_roots.append(game_root)
	if game_root.is_empty() or not game_roots.has(game_root):
		if not last_root.is_empty() and game_roots.has(last_root):
			game_root = last_root
		else:
			game_root = game_roots[0]
	if last_root.is_empty() or not game_roots.has(last_root):
		last_root = game_root
	if last_username.strip_edges().is_empty():
		last_username = "Player"


func save_config() -> Error:
	if game_roots.is_empty() and not game_root.is_empty():
		game_roots.clear()
		game_roots.append(game_root)
	var cfg := ConfigFile.new()
	cfg.set_value("launcher", "game_root", game_root)
	cfg.set_value("launcher", "game_roots", PackedStringArray(game_roots))
	cfg.set_value("launcher", "last_root", last_root)
	cfg.set_value("launcher", "last_version", last_version)
	cfg.set_value("launcher", "last_instance", last_instance)
	cfg.set_value("launcher", "last_username", last_username)
	cfg.set_value("launcher", "max_memory_mb", max_memory_mb)
	cfg.set_value("java", "mode", java_mode)
	cfg.set_value("java", "path", java_path)
	cfg.set_value("ui", "reduce_motion", reduce_motion)
	cfg.set_value("ui", "low_spec", low_spec)
	var err := cfg.save(config_path)
	if err != OK:
		printerr("[ConfigManager] 保存全局配置失败：%s（%s）" % [error_string(err), config_path])
	return err


func set_game_root(path: String) -> String:
	var p := _normalize_root(path)
	game_roots.clear()
	if not p.is_empty():
		game_roots.append(p)
	game_root = p
	last_root = p
	save_config()
	return game_root


func add_game_root(path: String) -> bool:
	var p := _normalize_root(path)
	if p.is_empty() or game_roots.has(p):
		return false
	game_roots.append(p)
	game_root = p
	last_root = p
	save_config()
	return true


func remove_game_root(path: String) -> bool:
	var p := _normalize_root(path)
	var idx := game_roots.find(p)
	if idx < 0:
		return false
	game_roots.remove_at(idx)
	if game_roots.is_empty():
		game_root = ""
		last_root = ""
	else:
		game_root = game_roots[0]
		last_root = game_root
	save_config()
	return true


func set_current_root(path: String) -> void:
	var p := _normalize_root(path)
	if p.is_empty():
		return
	game_root = p
	last_root = p


func _normalize_root(path: String) -> String:
	var p := str(path).replace("\\", "/")
	while p.length() > 1 and p.ends_with("/") and not p.ends_with(":/"):
		p = p.substr(0, p.length() - 1)
	return p


## 兼容用户选择 .minecraft 的上级目录：如果 path/versions 不存在但 path/.minecraft/versions 存在，
## 返回 path/.minecraft。否则原样返回，由扫描器给出可读错误。
func resolve_game_root(path: String) -> String:
	var p := str(path).replace("\\", "/")
	while p.length() > 1 and p.ends_with("/") and not p.ends_with(":/"):
		p = p.substr(0, p.length() - 1)
	if DirAccess.dir_exists_absolute(p + "/versions"):
		return p
	if DirAccess.dir_exists_absolute(p + "/.minecraft/versions"):
		return p + "/.minecraft"
	return p


func _guess_game_root() -> String:
	var appdata := OS.get_environment("APPDATA")
	if not appdata.is_empty():
		var p := appdata.replace("\\", "/") + "/.minecraft"
		if DirAccess.dir_exists_absolute(p):
			return p
	var home := OS.get_environment("HOME")
	if home.is_empty():
		home = OS.get_environment("USERPROFILE")
	if not home.is_empty():
		var q := home.replace("\\", "/") + "/.minecraft"
		if DirAccess.dir_exists_absolute(q):
			return q
	var fallback := ProjectSettings.globalize_path("user://.minecraft").replace("\\", "/")
	DirAccess.make_dir_recursive_absolute(fallback + "/versions")
	return fallback
