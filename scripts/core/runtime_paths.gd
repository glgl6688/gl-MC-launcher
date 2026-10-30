class_name RuntimePaths
extends RefCounted
## 启动器自己的数据目录：优先放在启动器所在目录（开发时为项目根目录），
## 避免默认写入 C 盘的 user://（AppData）。只有在启动器目录不可写时才回退。

const DATA_DIR_NAME := "launcher-data"


static func launcher_dir() -> String:
	var base := ""
	if OS.has_feature("editor"):
		base = ProjectSettings.globalize_path("res://")
	else:
		base = OS.get_executable_path().get_base_dir()
	return _normalize(base)


static func data_dir() -> String:
	var base := launcher_dir()
	if base.is_empty():
		return "user://" + DATA_DIR_NAME
	if _is_writable(base):
		return base
	var fallback := "user://" + DATA_DIR_NAME
	DirAccess.make_dir_recursive_absolute(fallback)
	return fallback


static func path(relative: String) -> String:
	return _join(data_dir(), relative)


static func legacy_user_path(relative: String) -> String:
	return _join(ProjectSettings.globalize_path("user://").replace("\\", "/"), relative)


static func ensure_writable() -> bool:
	var base := data_dir()
	DirAccess.make_dir_recursive_absolute(base)
	return _is_writable(base)


static func _is_writable(dir: String) -> bool:
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK:
		return false
	var probe := _join(dir, ".gl-write-test")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string("ok")
	f.close()
	DirAccess.remove_absolute(probe)
	return true


static func _join(base: String, relative: String) -> String:
	var b := _normalize(base)
	var r := str(relative).replace("\\", "/")
	if r.begins_with("/"):
		r = r.substr(1)
	if b.is_empty() or b == "user:":
		return r
	return b.trim_suffix("/") + "/" + r


static func _normalize(p: String) -> String:
	var s := str(p).replace("\\", "/")
	while s.length() > 1 and s.ends_with("/") and not s.ends_with(":/"):
		s = s.substr(0, s.length() - 1)
	return s
