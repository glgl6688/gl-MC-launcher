extends Node
## 启动器日志：<启动器目录>/logs/launcher-YYYYMMDD.log
## 开发时“启动器目录”为项目根目录；导出后为可执行文件所在目录。
## 如果该目录不可写，自动回退到 user://logs。

signal line_added(line: String)

const MAX_AGE_SECONDS := 7 * 24 * 60 * 60
const MAX_UI_LINES := 3000

var entries: Array = []
var logs_root := ""
var using_fallback := false

var _file: FileAccess = null
var _file_path := ""
var _file_date := ""


func _ready() -> void:
	logs_root = _choose_logs_root()
	DirAccess.make_dir_recursive_absolute(logs_root)
	_cleanup_old_logs()
	_open_today_file()
	info("启动器日志已就绪：%s" % _file_path)
	if using_fallback:
		warn("启动器目录不可写，日志已回退到 user://logs")


func launcher_dir() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/")
	return OS.get_executable_path().get_base_dir().replace("\\", "/").trim_suffix("/")


func _choose_logs_root() -> String:
	var candidate := launcher_dir() + "/logs"
	var err := DirAccess.make_dir_recursive_absolute(candidate)
	if err == OK:
		var probe := candidate + "/.write_test"
		var f := FileAccess.open(probe, FileAccess.WRITE)
		if f != null:
			f.store_string("ok")
			f.close()
			DirAccess.remove_absolute(probe)
			return candidate
	using_fallback = true
	return "user://logs"


func info(message: String) -> void:
	_write("INFO", message)


func warn(message: String) -> void:
	_write("WARN", message)


func error(message: String) -> void:
	_write("ERROR", message)


func _write(level: String, message: String) -> void:
	var now := Time.get_datetime_dict_from_system()
	var date := "%04d%02d%02d" % [int(now.year), int(now.month), int(now.day)]
	var stamp := "%04d-%02d-%02d %02d:%02d:%02d" % [
		int(now.year), int(now.month), int(now.day),
		int(now.hour), int(now.minute), int(now.second),
	]
	if date != _file_date:
		_open_today_file()
	var line := "[%s][%s] %s" % [stamp, level, message]
	if level == "ERROR":
		printerr(line)
	else:
		print(line)
	if _file != null:
		_file.store_line(line)
		_file.flush()
	entries.append(line)
	if entries.size() > MAX_UI_LINES:
		entries = entries.slice(entries.size() - MAX_UI_LINES)
	line_added.emit(line)


func _open_today_file() -> void:
	if _file != null:
		_file.close()
	var now := Time.get_datetime_dict_from_system()
	_file_date = "%04d%02d%02d" % [int(now.year), int(now.month), int(now.day)]
	_file_path = "%s/launcher-%s.log" % [logs_root, _file_date]
	_file = FileAccess.open(_file_path, FileAccess.READ_WRITE)
	if _file == null:
		_file = FileAccess.open(_file_path, FileAccess.WRITE)
	if _file != null:
		_file.seek_end()


func get_today_history(max_lines: int = 500) -> String:
	var p := "%s/launcher-%s.log" % [logs_root, _file_date]
	if not FileAccess.file_exists(p):
		return ""
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	var lines := text.split("\n", true)
	if lines.size() > max_lines:
		lines = lines.slice(lines.size() - max_lines)
	return "\n".join(lines)


func logs_global_dir() -> String:
	return ProjectSettings.globalize_path(logs_root).replace("\\", "/")


## 游戏进程输出日志也放在启动器目录下，便于和启动器日志一起查看。
func game_log_path(instance_name: String) -> String:
	var safe := str(instance_name).strip_edges()
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		safe = safe.replace(ch, "_")
	if safe.is_empty():
		safe = "instance"
	var dir := "%s/instances/%s" % [logs_root, safe]
	DirAccess.make_dir_recursive_absolute(dir)
	return dir + "/latest.log"


func open_logs_folder() -> void:
	var err := OS.shell_open(logs_global_dir())
	if err != OK:
		error("无法打开日志目录：%s（%s）" % [logs_global_dir(), error_string(err)])


func _cleanup_old_logs() -> void:
	var dir := DirAccess.open(logs_root)
	if dir == null:
		return
	var now := int(Time.get_unix_time_from_system())
	for name in dir.get_files():
		if not name.begins_with("launcher-") or not name.ends_with(".log"):
			continue
		var path := logs_root + "/" + name
		var modified := int(FileAccess.get_modified_time(path))
		if modified > 0 and now - modified > MAX_AGE_SECONDS:
			DirAccess.remove_absolute(path)
