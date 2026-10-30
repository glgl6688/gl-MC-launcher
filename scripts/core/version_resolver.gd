class_name VersionResolver
extends RefCounted
## 读取版本 JSON、合并 inheritsFrom 继承链、解析运行库路径、解压本地原生库。
## 只读取本地文件，不做任何下载。

const FileUtilsScript = preload("res://scripts/core/file_utils.gd")
const ErrorInfoScript = preload("res://scripts/core/error_info.gd")
const MAX_INHERIT_DEPTH := 10


static func load_merged(source_root: String, version_id: String) -> Dictionary:
	var root := FileUtilsScript.normalize(source_root)
	var versions_dir := FileUtilsScript.join(root, "versions")
	var chain: Array[Dictionary] = []
	var visited := {}
	var current := version_id
	while not current.is_empty():
		if visited.has(current):
			return _fail("LAUNCH_CONFIG_INVALID", {
				"name": version_id,
				"reason": "版本继承链出现循环：" + current,
			})
		if chain.size() >= MAX_INHERIT_DEPTH:
			return _fail("LAUNCH_CONFIG_INVALID", {
				"name": version_id,
				"reason": "版本继承层数超过 %d 层" % MAX_INHERIT_DEPTH,
			})
		visited[current] = true
		var json_path := FileUtilsScript.join(versions_dir, current + "/" + current + ".json")
		var parsed := _read_json(json_path)
		if not bool(parsed.get("ok", false)):
			return _fail(str(parsed.get("code", "LAUNCH_CONFIG_INVALID")), {
				"name": current,
				"path": json_path,
				"reason": str(parsed.get("reason", "")),
			})
		var data: Dictionary = parsed.get("data", {})
		var entry := data.duplicate(true)
		entry["__id"] = current
		chain.append(entry)
		current = str(data.get("inheritsFrom", ""))
	var merged: Dictionary = {}
	for i in range(chain.size() - 1, -1, -1):
		merged = _merge(merged, chain[i])
	merged.erase("inheritsFrom")
	var jar_id := str(merged.get("jar", version_id))
	if jar_id.is_empty():
		jar_id = version_id
	var jar_path := FileUtilsScript.join(versions_dir, jar_id + "/" + jar_id + ".jar")
	if not FileAccess.file_exists(jar_path):
		jar_path = FileUtilsScript.join(versions_dir, version_id + "/" + version_id + ".jar")
	return {
		"ok": true,
		"json": merged,
		"jar_path": jar_path,
		"chain": chain,
		"error": {},
	}


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "code": "VERSION_JSON_MISSING", "reason": "文件不存在", "path": path}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "code": "VERSION_JSON_INVALID", "reason": error_string(FileAccess.get_open_error())}
	var text := f.get_as_text()
	f.close()
	var parser := JSON.new()
	var err := parser.parse(text)
	if err != OK:
		return {
			"ok": false,
			"code": "VERSION_JSON_INVALID",
			"reason": "第 %d 行：%s" % [parser.get_error_line(), parser.get_error_message()],
		}
	if not (parser.data is Dictionary):
		return {"ok": false, "code": "VERSION_JSON_INVALID", "reason": "JSON 根节点不是对象"}
	return {"ok": true, "data": parser.data}


static func _merge(base: Dictionary, child: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for key in child.keys():
		if key == "libraries":
			var child_libs: Array = child.get("libraries", []) if child.get("libraries", []) is Array else []
			var base_libs: Array = out.get("libraries", []) if out.get("libraries", []) is Array else []
			# 单份 JSON 内部也可能重复（例如 Fabric 整合安装把 ASM 9.6 和 9.10.1 都写进去）。
			# 先各自按 group:artifact[:classifier] 去重，保留后者；再合并时子版本优先。
			child_libs = _dedupe_library_list(child_libs)
			base_libs = _dedupe_library_list(base_libs)
			var combined: Array = []
			var keys := {}
			for lib in child_libs + base_libs:
				if not (lib is Dictionary):
					continue
				var lib_key := _library_key(lib)
				if not lib_key.is_empty() and keys.has(lib_key):
					continue
				keys[lib_key] = true
				combined.append(lib)
			out["libraries"] = combined
		elif key == "arguments":
			var cargs: Dictionary = child.get("arguments", {}) if child.get("arguments", {}) is Dictionary else {}
			var bargs: Dictionary = out.get("arguments", {}) if out.get("arguments", {}) is Dictionary else {}
			var args_out := bargs.duplicate(true)
			for group in cargs.keys():
				var cgroup: Array = cargs[group] if cargs[group] is Array else []
				var bgroup: Array = args_out.get(group, []) if args_out.get(group, []) is Array else []
				args_out[group] = bgroup + cgroup
			out["arguments"] = args_out
		else:
			out[key] = child[key]
	return out


static func _dedupe_library_list(libs: Array) -> Array:
	var out: Array = []
	var index_by_key := {}
	for lib in libs:
		if not (lib is Dictionary):
			out.append(lib)
			continue
		var key := _library_key(lib)
		if key.is_empty():
			out.append(lib)
			continue
		if index_by_key.has(key):
			# 同一 JSON 内重复时保留后出现的条目（加载器通常追加在 Mojang 条目之后）。
			out[int(index_by_key[key])] = lib
		else:
			index_by_key[key] = out.size()
			out.append(lib)
	return out


static func _library_key(lib: Dictionary) -> String:
	# 加载器版本经常覆盖原版依赖（例如 ASM 9.10.1 覆盖 1.21.4 的 9.6）。
	# 仅按完整 name 去重会把两个版本都放进 classpath，导致 duplicate class 错误。
	# 因此按 group:artifact[:classifier] 去重，子版本在前、优先保留。
	var name := str(lib.get("name", ""))
	if name.is_empty():
		return ""
	var parts := name.split(":")
	if parts.size() < 3:
		return name
	var key := parts[0] + ":" + parts[1]
	if parts.size() >= 4:
		key += ":" + parts[3]
	return key


static func _fail(code: String, ctx: Dictionary) -> Dictionary:
	return {"ok": false, "json": {}, "jar_path": "", "chain": [], "error": ErrorInfoScript.make(code, ctx)}


static func os_key() -> String:
	match OS.get_name():
		"Windows":
			return "windows"
		"macOS":
			return "osx"
		"Linux":
			return "linux"
		_:
			return OS.get_name().to_lower()


static func os_arch() -> String:
	var arch := Engine.get_architecture_name()
	if arch == "x86_64" or arch == "amd64":
		return "x86_64"
	if arch == "arm64" or arch == "aarch64":
		return "arm64"
	return arch


static func required_java(data: Dictionary) -> int:
	if data.has("javaVersion") and data["javaVersion"] is Dictionary:
		var major := int(data["javaVersion"].get("majorVersion", 0))
		if major > 0:
			return major
	return 8


static func asset_index_id(data: Dictionary) -> String:
	if data.has("assetIndex") and data["assetIndex"] is Dictionary:
		var id := str(data["assetIndex"].get("id", ""))
		if not id.is_empty():
			return id
	return str(data.get("assets", ""))


static func rules_allow(rules: Array, features: Dictionary = {}) -> bool:
	if rules.is_empty():
		return true
	var allowed := false
	for rule in rules:
		if not (rule is Dictionary):
			continue
		if not _rule_matches(rule, features):
			continue
		var action := str(rule.get("action", "allow"))
		if action == "deny":
			return false
		allowed = true
	return allowed


static func _rule_matches(rule: Dictionary, features: Dictionary) -> bool:
	if rule.has("os") and rule["os"] is Dictionary:
		var osd: Dictionary = rule["os"]
		if osd.has("name") and str(osd["name"]) != os_key():
			return false
		if osd.has("arch"):
			var want := str(osd["arch"]).replace("${arch}", "64" if os_arch() != "x86" else "32")
			if want != os_arch():
				return false
	if rule.has("features") and rule["features"] is Dictionary:
		var need: Dictionary = rule["features"]
		for key in need.keys():
			if bool(need[key]) and not bool(features.get(str(key), false)):
				return false
	return true


static func library_allowed(lib: Dictionary, features: Dictionary = {}) -> bool:
	var rules: Array = lib.get("rules", []) if lib.get("rules", []) is Array else []
	return rules_allow(rules, features)


static func native_classifier(lib: Dictionary) -> String:
	if not (lib.get("natives", {}) is Dictionary):
		return ""
	var natives: Dictionary = lib.get("natives", {})
	var classifier := str(natives.get(os_key(), ""))
	if classifier.is_empty():
		return ""
	var arch := "64" if os_arch() != "x86" else "32"
	return classifier.replace("${arch}", arch)


static func artifact_path(source_root: String, lib: Dictionary) -> String:
	var libs_dir := FileUtilsScript.join(source_root, "libraries")
	var downloads: Variant = lib.get("downloads", {})
	if downloads is Dictionary:
		var artifact: Variant = downloads.get("artifact", {})
		if artifact is Dictionary and artifact.has("path"):
			return FileUtilsScript.join(libs_dir, str(artifact["path"]))
	return FileUtilsScript.join(libs_dir, maven_to_path(str(lib.get("name", ""))))


static func native_path(source_root: String, lib: Dictionary, classifier: String) -> String:
	var libs_dir := FileUtilsScript.join(source_root, "libraries")
	var downloads: Variant = lib.get("downloads", {})
	if downloads is Dictionary and downloads.get("classifiers", {}) is Dictionary:
		var classifiers: Dictionary = downloads.get("classifiers", {})
		var info: Variant = classifiers.get(classifier, {})
		if info is Dictionary and info.has("path"):
			return FileUtilsScript.join(libs_dir, str(info["path"]))
	var name := str(lib.get("name", ""))
	var parts := name.split(":")
	if parts.size() >= 3:
		var group := parts[0].replace(".", "/")
		var artifact := parts[1]
		var version := parts[2]
		return FileUtilsScript.join(libs_dir, "%s/%s/%s/%s-%s-%s.jar" % [group, artifact, version, artifact, version, classifier])
	return ""


static func maven_to_path(name: String) -> String:
	var clean := name
	var ext := "jar"
	if clean.contains("@"):
		var pieces := clean.split("@")
		clean = pieces[0]
		if pieces.size() > 1:
			ext = pieces[1]
	var parts := clean.split(":")
	if parts.size() < 3:
		return ""
	var group := parts[0].replace(".", "/")
	var artifact := parts[1]
	var version := parts[2]
	var classifier := ""
	if parts.size() >= 4:
		classifier = parts[3]
	var file := "%s-%s" % [artifact, version]
	if not classifier.is_empty():
		file += "-" + classifier
	file += "." + ext
	return "%s/%s/%s/%s" % [group, artifact, version, file]


## 把版本 JSON 声明的传统 natives（<1.19 常见）解压到实例目录。
## 返回 {ok, extracted, error, warnings}
static func extract_natives_from(source_root: String, libs: Array, natives_dir: String, warnings: Array) -> Dictionary:
	var dir := FileUtilsScript.normalize(natives_dir)
	var mk := FileUtilsScript.ensure_dir(dir)
	if mk != OK:
		return {
			"ok": false,
			"extracted": 0,
			"error": ErrorInfoScript.make("NATIVES_EXTRACT_FAILED", {
				"path": dir,
				"reason": error_string(mk),
			}),
		}
	var suffix := ".dll"
	if OS.get_name() == "Linux":
		suffix = ".so"
	elif OS.get_name() == "macOS":
		suffix = ".dylib"
	var extracted := 0
	var declared_native_libs := 0
	for lib in libs:
		if not (lib is Dictionary) or not library_allowed(lib):
			continue
		var classifier := native_classifier(lib)
		if classifier.is_empty():
			continue
		declared_native_libs += 1
		var jar := native_path(source_root, lib, classifier)
		if jar.is_empty() or not FileAccess.file_exists(jar):
			warnings.append("原生库缺失，已跳过：" + jar)
			continue
		var z := ZIPReader.new()
		var open_err := z.open(jar)
		if open_err != OK:
			warnings.append("无法打开原生库：%s（%s）" % [jar, error_string(open_err)])
			continue
		for entry in z.get_files():
			var entry_name := str(entry)
			if entry_name.ends_with("/") or entry_name.begins_with("META-INF/"):
				continue
			if not entry_name.to_lower().ends_with(suffix):
				continue
			var bytes := z.read_file(entry_name)
			if bytes.is_empty():
				continue
			var target := FileUtilsScript.join(dir, entry_name.get_file())
			var out := FileAccess.open(target, FileAccess.WRITE)
			if out == null:
				warnings.append("无法写入原生库文件：" + target)
				continue
			out.store_buffer(bytes)
			out.close()
			extracted += 1
		z.close()
	if extracted == 0 and declared_native_libs > 0:
		warnings.append("版本声明了原生库，但没有找到可解压的 " + suffix + " 文件。")
	return {"ok": true, "extracted": extracted, "error": {}, "warnings": warnings}
