class_name InstanceConfig
extends RefCounted
## 版本设置：默认保存在 <版本目录>/gl-instance.json；旧 instances/<实例名>/instance.json 仅用于迁移。

const FILE_NAME := "instance.json"
const VERSION_CONFIG_NAME := "gl-instance.json"
const ACCOUNT_MODES := ["online", "offline", "thirdparty"]
const JAVA_MODES := ["auto", "manual"]
const RESERVED_NAMES := [
	"CON", "PRN", "AUX", "NUL",
	"COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
	"LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
]

const FileUtilsScript = preload("res://scripts/core/file_utils.gd")

var version_id := ""
var source_root := ""
var account_mode := "offline"
var username := "Player"
var auth_url := ""
var authlib_jar := ""
var java_mode := "auto"
var java_path := ""
var isolate := true
var game_dir_mode := "version"
var instance_name := ""
var max_memory_mb := 2048
var auto_chinese := true
var created_at := ""
var last_launch := ""
var instance_dir := ""


static func create(p_version_id: String, p_instance_name: String = "") -> RefCounted:
	var cfg = _new_instance()
	cfg.version_id = p_version_id
	cfg.instance_name = p_instance_name if not p_instance_name.is_empty() else p_version_id
	cfg.created_at = Time.get_datetime_string_from_system(true)
	cfg.normalize()
	return cfg


static func from_dict(data: Dictionary, p_dir: String = "") -> RefCounted:
	var cfg = _new_instance()
	cfg.version_id = str(data.get("version_id", ""))
	cfg.source_root = str(data.get("source_root", "")).replace("\\", "/")
	cfg.account_mode = str(data.get("account_mode", "offline"))
	cfg.username = str(data.get("username", "Player"))
	cfg.auth_url = str(data.get("auth_url", ""))
	cfg.authlib_jar = str(data.get("authlib_jar", ""))
	cfg.java_mode = str(data.get("java_mode", "auto"))
	cfg.java_path = str(data.get("java_path", ""))
	cfg.isolate = bool(data.get("isolate", true))
	cfg.game_dir_mode = str(data.get("game_dir_mode", "version"))
	cfg.instance_name = str(data.get("instance_name", ""))
	cfg.max_memory_mb = int(data.get("max_memory_mb", 2048))
	cfg.auto_chinese = bool(data.get("auto_chinese", true))
	cfg.created_at = str(data.get("created_at", ""))
	cfg.last_launch = str(data.get("last_launch", ""))
	cfg.instance_dir = p_dir
	cfg.normalize()
	return cfg


## 通过脚本路径实例化自身，避免依赖全局类名缓存（直接运行项目时更稳）。
static func _new_instance() -> RefCounted:
	var script: Script = load("res://scripts/core/instance_config.gd")
	return script.new()


func normalize() -> void:
	if account_mode not in ACCOUNT_MODES:
		account_mode = "offline"
	if java_mode not in JAVA_MODES:
		java_mode = "auto"
	if game_dir_mode not in ["version", "instance", "shared"]:
		game_dir_mode = "version"
	if username.strip_edges().is_empty():
		username = "Player"
	max_memory_mb = clampi(max_memory_mb, 512, 32768)
	if instance_name.strip_edges().is_empty():
		instance_name = version_id if not version_id.is_empty() else "instance"
	if created_at.is_empty():
		created_at = Time.get_datetime_string_from_system(true)


func to_dict() -> Dictionary:
	return {
		"version_id": version_id,
		"source_root": source_root,
		"account_mode": account_mode,
		"username": username,
		"auth_url": auth_url,
		"authlib_jar": authlib_jar,
		"java_mode": java_mode,
		"java_path": java_path,
		"isolate": isolate,
		"game_dir_mode": game_dir_mode,
		"instance_name": instance_name,
		"max_memory_mb": max_memory_mb,
		"auto_chinese": auto_chinese,
		"created_at": created_at,
		"last_launch": last_launch,
	}


func config_path() -> String:
	if instance_dir.is_empty():
		return ""
	return FileUtilsScript.join(instance_dir, FILE_NAME)


func save() -> Dictionary:
	if instance_dir.is_empty():
		return {"ok": false, "path": "", "reason": "实例目录为空"}
	var path := config_path()
	var mk := FileUtilsScript.ensure_dir(instance_dir)
	if mk != OK:
		return {"ok": false, "path": path, "reason": "无法创建实例目录：" + error_string(mk)}
	var text := JSON.stringify(to_dict(), "\t")
	var written := FileUtilsScript.write_text(path, text + "\n")
	return {"ok": bool(written.get("ok", false)), "path": path, "reason": str(written.get("error", ""))}


func effective_game_dir(source_root: String) -> String:
	# 实例配置就放在版本目录里，游戏目录也固定为版本目录，不再让用户选择。
	# 这样 saves/、mods/、options.txt 都直接跟着版本走，也不会写到 AppData。
	return FileUtilsScript.join(source_root, "versions/" + version_id)


static func version_config_path(version_dir: String) -> String:
	return FileUtilsScript.join(version_dir, VERSION_CONFIG_NAME)


## 读取某个版本目录下的 gl-instance.json；不存在时返回 found=false，由调用方迁移旧配置或创建默认值。
static func load_for_version(version_dir: String, p_version_id: String = "", p_source_root: String = "") -> Dictionary:
	var path := version_config_path(version_dir)
	var loaded := load_file(path)
	if bool(loaded.get("ok", false)):
		var cfg = loaded.get("config", null)
		if cfg != null:
			if str(cfg.version_id).is_empty():
				cfg.version_id = p_version_id
			if not p_source_root.is_empty():
				cfg.source_root = p_source_root
			cfg.instance_dir = FileUtilsScript.normalize(version_dir)
			cfg.normalize()
			return {"ok": true, "found": true, "path": path, "config": cfg}
	if FileAccess.file_exists(path):
		FileUtilsScript.backup_file(path)
	return {"ok": false, "found": false, "path": path, "config": null, "reason": str(loaded.get("reason", ""))}


## 保存到版本目录下的 gl-instance.json。
func save_to(version_dir: String) -> Dictionary:
	var dir := FileUtilsScript.normalize(version_dir)
	if dir.is_empty():
		return {"ok": false, "path": "", "reason": "版本目录为空"}
	var mk := FileUtilsScript.ensure_dir(dir)
	if mk != OK:
		return {"ok": false, "path": "", "reason": "无法创建版本目录：" + error_string(mk)}
	instance_dir = dir
	var path := version_config_path(dir)
	var written := FileUtilsScript.write_text(path, JSON.stringify(to_dict(), "\t") + "\n")
	return {"ok": bool(written.get("ok", false)), "path": path, "reason": str(written.get("error", ""))}


## 确保某个游戏目录（版本目录 / 实例目录 / 共享根目录）拥有标准子目录。
static func ensure_game_dirs(game_dir: String) -> Error:
	var base := FileUtilsScript.normalize(game_dir)
	if base.is_empty():
		return ERR_INVALID_PARAMETER
	return FileUtilsScript.ensure_dirs(PackedStringArray([
		base,
		FileUtilsScript.join(base, "mods"),
		FileUtilsScript.join(base, "saves"),
		FileUtilsScript.join(base, "resourcepacks"),
		FileUtilsScript.join(base, "shaderpacks"),
		FileUtilsScript.join(base, "config"),
		FileUtilsScript.join(base, "logs"),
	]))


static func load_file(path: String) -> Dictionary:
	var p := FileUtilsScript.normalize(path)
	var dir := p.get_base_dir()
	if not FileAccess.file_exists(p):
		return {"ok": false, "reason": "文件不存在", "path": p, "config": null}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {"ok": false, "reason": error_string(FileAccess.get_open_error()), "path": p, "config": null}
	var text := f.get_as_text()
	f.close()
	var parser := JSON.new()
	var err := parser.parse(text)
	if err != OK:
		return {
			"ok": false,
			"reason": "第 %d 行：%s" % [parser.get_error_line(), parser.get_error_message()],
			"path": p,
			"config": null,
		}
	if not (parser.data is Dictionary):
		return {"ok": false, "reason": "JSON 根节点不是对象", "path": p, "config": null}
	var cfg = from_dict(parser.data, dir)
	return {"ok": true, "reason": "", "path": p, "config": cfg}


## 在 instances 目录中查找属于指定版本的实例，返回最近使用的那个。
static func find_for_version(instances_root: String, version_id: String, source_root: String = "") -> Dictionary:
	var best: Dictionary = {"found": false, "dir": "", "config": null}
	var best_key := ""
	var root := FileUtilsScript.normalize(instances_root)
	for name in FileUtilsScript.list_dirs(root):
		var dir := FileUtilsScript.join(root, name)
		var file := FileUtilsScript.join(dir, FILE_NAME)
		if not FileAccess.file_exists(file):
			continue
		var loaded := load_file(file)
		if not bool(loaded.get("ok", false)):
			continue
		var cfg = loaded.get("config", null)
		if cfg == null or cfg.version_id != version_id:
			continue
		if not source_root.is_empty() and not str(cfg.source_root).is_empty() and FileUtilsScript.normalize(str(cfg.source_root)) != FileUtilsScript.normalize(source_root):
			continue
		var key: String = cfg.last_launch
		if key.is_empty():
			key = "0"
		if not best.get("found", false) or key > best_key:
			best = {"found": true, "dir": dir, "config": cfg}
			best_key = key
	return best


static func default_instance_dir(instances_root: String, name: String) -> String:
	return FileUtilsScript.join(instances_root, sanitize_name(name))


static func sanitize_name(name: String) -> String:
	var n := name.strip_edges()
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		n = n.replace(ch, "_")
	if n.is_empty():
		n = "instance"
	if n == "." or n == "..":
		n = "instance"
	if n.length() > 64:
		n = n.substr(0, 64)
	return n


static func is_valid_name(name: String) -> bool:
	if name != name.strip_edges():
		return false
	if name.is_empty() or name.length() > 64:
		return false
	if name == "." or name == "..":
		return false
	if name.ends_with(".") or name.ends_with(" "):
		return false
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		if name.contains(ch):
			return false
	var upper := name.to_upper()
	for reserved in RESERVED_NAMES:
		if upper == reserved or upper.begins_with(reserved + "."):
			return false
	return true


static func name_rule_text() -> String:
	return "1-64 个字符，不能是 . 或 ..，不能以点或空格结尾，不能包含 / \\ : * ? \" < > |，也不能使用 Windows 保留名（如 CON、NUL）。"


static func ensure_layout(dir: String) -> Error:
	var base := FileUtilsScript.normalize(dir)
	if base.is_empty():
		return ERR_INVALID_PARAMETER
	var game := FileUtilsScript.join(base, ".minecraft")
	var dirs := PackedStringArray([
		base,
		FileUtilsScript.join(base, "logs"),
		FileUtilsScript.join(base, "bin"),
		game,
		FileUtilsScript.join(game, "mods"),
		FileUtilsScript.join(game, "shaderpacks"),
		FileUtilsScript.join(game, "resourcepacks"),
		FileUtilsScript.join(game, "saves"),
		FileUtilsScript.join(game, "config"),
		FileUtilsScript.join(game, "logs"),
	])
	return FileUtilsScript.ensure_dirs(dirs)


## 扫描所有实例，供“整合包目标选择”对话框使用。
static func list_instances(instances_root: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var root := FileUtilsScript.normalize(instances_root)
	for name in FileUtilsScript.list_dirs(root):
		var dir := FileUtilsScript.join(root, name)
		var file := FileUtilsScript.join(dir, FILE_NAME)
		if not FileAccess.file_exists(file):
			continue
		var loaded := load_file(file)
		if not bool(loaded.get("ok", false)):
			continue
		var cfg = loaded.get("config", null)
		if cfg == null:
			continue
		out.append({
			"name": cfg.instance_name,
			"version_id": cfg.version_id,
			"dir": dir,
			"last_launch": cfg.last_launch,
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", ""))) < 0
	)
	return out
