class_name ComponentManager
extends RefCounted
## 版本组件统计与“移出”操作。移出 = 移动到 .minecraft 外面的备份目录，不删除。

const FileUtilsScript = preload("res://scripts/core/file_utils.gd")

const CATEGORIES := [
	{"key": "mods", "label": "Mod"},
	{"key": "shaderpacks", "label": "光影"},
	{"key": "resourcepacks", "label": "材质"},
	{"key": "saves", "label": "存档"},
]


static func list_components(version_dir: String) -> Dictionary:
	var items: Array[Dictionary] = []
	var counts := {}
	var base := FileUtilsScript.normalize(version_dir)
	for spec in CATEGORIES:
		var key := str(spec["key"])
		var label := str(spec["label"])
		var dir_path := FileUtilsScript.join(base, key)
		var n := 0
		var dir := DirAccess.open(dir_path)
		if dir != null:
			for file in dir.get_files():
				var name := str(file)
				items.append({
					"category": key, "label": label, "name": name,
					"path": FileUtilsScript.join(dir_path, name), "dir": false,
				})
				n += 1
			for sub in dir.get_directories():
				var name := str(sub)
				items.append({
					"category": key, "label": label, "name": name,
					"path": FileUtilsScript.join(dir_path, name), "dir": true,
				})
				n += 1
		counts[key] = n
	return {"ok": true, "items": items, "counts": counts, "dir": base}


static func move_selected(version_dir: String, game_root: String, version_id: String, paths: PackedStringArray) -> Dictionary:
	var base := FileUtilsScript.normalize(version_dir)
	var game := FileUtilsScript.to_global(game_root)
	var parent := game.get_base_dir()
	var safe_version := version_id.strip_edges()
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		safe_version = safe_version.replace(ch, "_")
	if safe_version.is_empty():
		safe_version = "version"
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "-").replace(" ", "_")
	var target_root := FileUtilsScript.join(parent, "gl-component-backup/" + game.get_file() + "/" + safe_version + "/" + stamp)
	var moved: Array[String] = []
	var errors: Array[String] = []
	for raw in paths:
		var p := FileUtilsScript.normalize(str(raw))
		if p.is_empty() or not p.begins_with(base.trim_suffix("/") + "/"):
			errors.append("拒绝移出版本目录之外的文件：" + p)
			continue
		var category := p.get_base_dir().get_file()
		var name := p.get_file()
		var dest_dir := FileUtilsScript.join(target_root, category)
		FileUtilsScript.ensure_dir(dest_dir)
		var dest := FileUtilsScript.join(dest_dir, name)
		var idx := 1
		while FileAccess.file_exists(dest) or DirAccess.dir_exists_absolute(dest):
			dest = FileUtilsScript.join(dest_dir, "%s (%d)%s" % [name.get_basename(), idx, name.get_extension().insert(0, ".") if not name.get_extension().is_empty() else ""])
			idx += 1
		var src_global := FileUtilsScript.to_global(p)
		var err := DirAccess.rename_absolute(src_global, dest)
		if err == OK:
			moved.append(p)
		else:
			errors.append("%s：%s" % [p, error_string(err)])
	return {
		"ok": errors.is_empty(),
		"moved": moved,
		"errors": errors,
		"target": target_root if not moved.is_empty() else "",
	}
