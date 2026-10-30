class_name VersionScanner
extends RefCounted
## 版本发现：只读取 <游戏根目录>/versions/*，校验 <id>.json 与 <id>.jar。
## 扫描本身是同步的；UI 层必须把它放进后台线程（ThreadTask）执行。
## 返回结构：
## { ok, versions: Array[Dictionary], versions_dir, root, error }
## 单个版本：{ id, name, dir, json_path, jar_path, usable, reason, type, inherits, required_java }

const FileUtilsScript = preload("res://scripts/core/file_utils.gd")
const ErrorInfoScript = preload("res://scripts/core/error_info.gd")
const VersionDiagnosticsScript = preload("res://scripts/core/version_diagnostics.gd")


static func scan_sync(root: String) -> Dictionary:
	var base := FileUtilsScript.normalize(root)
	var versions_dir := FileUtilsScript.join(base, "versions")
	if not DirAccess.dir_exists_absolute(versions_dir):
		return {
			"ok": false,
			"versions": [],
			"versions_dir": versions_dir,
			"root": base,
			"error": ErrorInfoScript.make("NO_VERSIONS_DIR", {"path": versions_dir}),
		}
	var dir := DirAccess.open(versions_dir)
	if dir == null:
		return {
			"ok": false,
			"versions": [],
			"versions_dir": versions_dir,
			"root": base,
			"error": ErrorInfoScript.make("VERSIONS_DIR_UNREADABLE", {
				"path": versions_dir,
				"reason": error_string(DirAccess.get_open_error()),
			}),
		}
	var ids: Array[String] = []
	for name in dir.get_directories():
		ids.append(str(name))
	ids.sort_custom(func(a: String, b: String) -> bool:
		return a.naturalnocasecmp_to(b) < 0
	)
	var versions: Array[Dictionary] = []
	for id in ids:
		versions.append(_inspect_version(versions_dir, id, base))
	return {
		"ok": true,
		"versions": versions,
		"versions_dir": versions_dir,
		"root": base,
		"error": {},
	}


## 扫描多个游戏文件夹，返回合并后的版本列表和每个文件夹的错误。
static func scan_roots(roots: PackedStringArray) -> Dictionary:
	var all: Array[Dictionary] = []
	var errors: Array[Dictionary] = []
	var valid_roots: Array[String] = []
	for root in roots:
		var res := scan_sync(str(root))
		valid_roots.append(FileUtilsScript.normalize(str(root)))
		if bool(res.get("ok", false)):
			for v in res.get("versions", []):
				if v is Dictionary:
					all.append(v)
		else:
			var err: Variant = res.get("error", {})
			if err is Dictionary:
				errors.append(err)
	return {
		"ok": true,
		"versions": all,
		"roots": valid_roots,
		"errors": errors,
		"versions_dir": "",
		"error": {},
	}


static func _inspect_version(versions_dir: String, id: String, root: String) -> Dictionary:
	var vdir := FileUtilsScript.join(versions_dir, id)
	var json_path := FileUtilsScript.join(vdir, id + ".json")
	var jar_path := FileUtilsScript.join(vdir, id + ".jar")
	var out := {
		"id": id,
		"name": id,
		"root": root,
		"root_name": root.get_file(),
		"dir": vdir,
		"json_path": json_path,
		"jar_path": jar_path,
		"usable": false,
		"reason": "",
		"fix_hint": "",
		"error_code": "",
		"issues": [],
		"type": "",
		"inherits": "",
		"required_java": 8,
		"has_asset_index": false,
		"has_game_data": _has_game_data(vdir),
		"mod_count": _count_children(FileUtilsScript.join(vdir, "mods"), "*.jar"),
		"shader_count": _count_children(FileUtilsScript.join(vdir, "shaderpacks")),
		"resourcepack_count": _count_children(FileUtilsScript.join(vdir, "resourcepacks")),
		"save_count": _count_children(FileUtilsScript.join(vdir, "saves")),
	}
	var component_text := _components_text(out)
	var has_json := FileAccess.file_exists(json_path)
	var has_jar := FileAccess.file_exists(jar_path)
	if not has_json and not has_jar:
		out["error_code"] = "VERSION_VANILLA_MISSING" if bool(out["has_game_data"]) else "VERSION_FILES_MISSING"
		out["reason"] = "缺少原版版本 JSON 与客户端 JAR（%s）。" % component_text
		out["fix_hint"] = "这不是完整游戏版本。请先用官方启动器或 PCL 安装对应的原版版本（确认 versions/<版本名>/ 下同时有 .json 和 .jar），再安装 Fabric/Forge；Mod 不能单独启动。"
		return out
	if not has_json:
		out["error_code"] = "VERSION_JSON_MISSING"
		out["reason"] = "缺少原版版本 JSON，只有 JAR；无法确定版本类型/主类（%s）。" % component_text
		out["fix_hint"] = "请补上原版版本 JSON，或重新安装该版本；只有 JAR 不能启动。"
		return out
	var parsed := _read_version_json(json_path)
	if not bool(parsed.get("ok", false)):
		out["error_code"] = "VERSION_JSON_INVALID"
		out["reason"] = str(parsed.get("reason", "JSON 解析失败")) + "（" + component_text + "）"
		out["fix_hint"] = "请修复或重新获取该版本的 JSON 文件；如果这是整合包文件夹，请先安装完整原版版本。"
		return out
	var data: Dictionary = parsed.get("data", {})
	out["type"] = str(data.get("type", ""))
	out["inherits"] = str(data.get("inheritsFrom", ""))
	out["required_java"] = _merged_required_java(versions_dir, data, 0)
	out["has_asset_index"] = _has_asset_index(data)
	var parent := str(data.get("inheritsFrom", ""))
	if not parent.is_empty():
		var parent_json := FileUtilsScript.join(versions_dir, parent + "/" + parent + ".json")
		if not FileAccess.file_exists(parent_json):
			out["error_code"] = "VERSION_PARENT_MISSING"
			out["reason"] = "依赖的父版本 %s 不存在（%s）。" % [parent, component_text]
			out["fix_hint"] = "请先安装 %s 原版版本，或把它的版本文件夹补到同一 versions 目录；Fabric/Forge 版本不能脱离父版本启动。" % parent
			return out
	if not has_jar:
		# 少量整合版本用 "jar" 指向父版本客户端；这种情况下父 JAR 存在即可。
		var jar_id := str(data.get("jar", ""))
		if not jar_id.is_empty():
			var alt := FileUtilsScript.join(versions_dir, jar_id + "/" + jar_id + ".jar")
			if FileAccess.file_exists(alt):
				out["jar_path"] = alt
				out["usable"] = true
				return out
		out["error_code"] = "VERSION_JAR_MISSING"
		out["reason"] = "缺少客户端 JAR，只有 JSON；不能启动（%s）。" % component_text
		out["fix_hint"] = "请补上原版客户端 JAR，或重新安装该版本；不要把 Mod 当成游戏本体。"
		return out
	var diag := VersionDiagnosticsScript.inspect(root, id, vdir)
	if not bool(diag.get("ok", false)):
		out["usable"] = false
		out["reason"] = str(diag.get("reason", "版本文件不完整"))
		out["fix_hint"] = str(diag.get("fix_hint", ""))
		out["error_code"] = str(diag.get("error_code", "VERSION_INVALID"))
		out["issues"] = diag.get("issues", [])
		return out
	out["usable"] = true
	return out


static func _components_text(entry: Dictionary) -> String:
	return "Mod %d 个、光影 %d 个、材质 %d 个、存档 %d 个" % [
		int(entry.get("mod_count", 0)), int(entry.get("shader_count", 0)),
		int(entry.get("resourcepack_count", 0)), int(entry.get("save_count", 0)),
	]


## 版本 JSON 经常通过 inheritsFrom 继承 Java 要求；UI 需要显示合并后的值。
static func _merged_required_java(versions_dir: String, data: Dictionary, depth: int) -> int:
	if data.has("javaVersion") and data["javaVersion"] is Dictionary:
		var major := int(data["javaVersion"].get("majorVersion", 0))
		if major > 0:
			return major
	var parent := str(data.get("inheritsFrom", ""))
	if depth >= 10 or parent.is_empty():
		return 8
	var parent_path := FileUtilsScript.join(versions_dir, parent + "/" + parent + ".json")
	if not FileAccess.file_exists(parent_path):
		return 8
	var parsed := _read_version_json(parent_path)
	if not bool(parsed.get("ok", false)):
		return 8
	return _merged_required_java(versions_dir, parsed.get("data", {}), depth + 1)


static func _read_version_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "reason": "无法读取文件：" + error_string(FileAccess.get_open_error())}
	var text := f.get_as_text()
	f.close()
	var parser := JSON.new()
	var err := parser.parse(text)
	if err != OK:
		return {
			"ok": false,
			"reason": "第 %d 行：%s" % [parser.get_error_line(), parser.get_error_message()],
		}
	var data: Variant = parser.data
	if not data is Dictionary:
		return {"ok": false, "reason": "JSON 根节点不是对象"}
	return {"ok": true, "data": data}


static func _has_asset_index(data: Dictionary) -> bool:
	if data.has("assetIndex") and data["assetIndex"] is Dictionary:
		return not str(data["assetIndex"].get("id", "")).is_empty()
	return not str(data.get("assets", "")).is_empty()


static func required_java_for(data: Dictionary) -> int:
	if data.has("javaVersion") and data["javaVersion"] is Dictionary:
		var major := int(data["javaVersion"].get("majorVersion", 0))
		if major > 0:
			return major
	return 8


static func usable_count(versions: Array) -> int:
	var n := 0
	for v in versions:
		if v is Dictionary and bool(v.get("usable", false)):
			n += 1
	return n


static func _has_game_data(version_dir: String) -> bool:
	for name in ["saves", "mods", "options.txt", "shaderpacks", "resourcepacks"]:
		var path := FileUtilsScript.join(version_dir, name)
		if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
			return true
	return false


static func _count_children(path: String, suffix: String = "") -> int:
	var dir := DirAccess.open(path)
	if dir == null:
		return 0
	var n := 0
	for file in dir.get_files():
		if suffix.is_empty() or str(file).to_lower().ends_with(suffix.trim_prefix("*").to_lower()):
			n += 1
	for sub in dir.get_directories():
		if suffix.is_empty():
			n += 1
	return n
