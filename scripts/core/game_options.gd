class_name GameOptions
extends RefCounted
## 首次/每次启动前确保游戏使用中文与 Unicode 字体。
## 只在用户勾选“自动设置游戏中文”时执行，不覆盖其他设置。

const FileUtilsScript = preload("res://scripts/core/file_utils.gd")


static func ensure_chinese(game_dir: String, source_root: String = "") -> Dictionary:
	var base := FileUtilsScript.normalize(game_dir)
	var path := FileUtilsScript.join(base, "options.txt")
	FileUtilsScript.ensure_dir(base)
	var created_from_shared := false
	if not FileAccess.file_exists(path):
		var shared := FileUtilsScript.join(source_root, "options.txt")
		if not source_root.is_empty() and FileAccess.file_exists(shared):
			var copy := FileUtilsScript.copy_file_chunked(shared, path)
			if bool(copy.get("ok", false)):
				created_from_shared = true
	var lines: PackedStringArray = []
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			lines = f.get_as_text().split("\n", true)
			f.close()
	var values := {}
	var order: Array[String] = []
	for line in lines:
		var trimmed := line.strip_edges()
		if trimmed.is_empty() or not trimmed.contains(":"):
			continue
		var key := trimmed.substr(0, trimmed.find(":"))
		if not values.has(key):
			order.append(key)
		values[key] = trimmed.substr(trimmed.find(":") + 1)
	var changed := created_from_shared
	if str(values.get("lang", "")) != "zh_cn":
		values["lang"] = "zh_cn"
		if not order.has("lang"):
			order.append("lang")
		changed = true
	if str(values.get("forceUnicodeFont", "")).to_lower() != "true":
		values["forceUnicodeFont"] = "true"
		if not order.has("forceUnicodeFont"):
			order.append("forceUnicodeFont")
		changed = true
	if not changed:
		return {"ok": true, "path": path, "changed": false, "error": ""}
	var out: Array[String] = []
	for key in order:
		out.append("%s:%s" % [key, str(values[key])])
	var written := FileUtilsScript.write_text(path, "\n".join(out) + "\n")
	return {
		"ok": bool(written.get("ok", false)),
		"path": path,
		"changed": changed,
		"error": str(written.get("error", "")),
	}
