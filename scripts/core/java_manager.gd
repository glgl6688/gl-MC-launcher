class_name JavaManager
extends RefCounted
## Java 检测与校验。
## 自动检测顺序：手动指定 -> JAVA_HOME -> PATH -> 常见安装目录 -> 官方启动器 runtime。
## 所有探测都通过 OS.execute("java", ["-version"]) 完成，必须放在后台线程执行。

const ErrorInfoScript = preload("res://scripts/core/error_info.gd")
const FileUtilsScript = preload("res://scripts/core/file_utils.gd")

const MAX_CANDIDATES := 60
const MAX_SCAN_ENTRIES := 400


static func probe(java_path: String) -> Dictionary:
	var path := FileUtilsScript.normalize(java_path)
	if path.is_empty():
		return {"ok": false, "error": ErrorInfoScript.make("JAVA_NOT_FOUND", {"hint": install_hint(), "path": suggested_path()})}
	if not FileAccess.file_exists(path):
		return {
			"ok": false,
			"error": ErrorInfoScript.make("JAVA_NOT_RUNNABLE", {
				"path": path,
				"detail": "文件不存在",
			}),
		}
	var output: Array = []
	var code := OS.execute(path, PackedStringArray(["-version"]), output, true)
	var text := ""
	for line in output:
		text += str(line) + "\n"
	text = text.strip_edges()
	if code != 0:
		return {
			"ok": false,
			"error": ErrorInfoScript.make("JAVA_NOT_RUNNABLE", {
				"path": path,
				"detail": "退出码 %d\n%s" % [code, text],
			}),
		}
	var major := parse_major(text)
	if major <= 0:
		return {
			"ok": false,
			"error": ErrorInfoScript.make("JAVA_VERSION_UNKNOWN", {
				"path": path,
				"detail": text if not text.is_empty() else "（无输出）",
			}),
		}
	var first_line := ""
	for line in text.split("\n", true):
		if not line.strip_edges().is_empty():
			first_line = line.strip_edges()
			break
	return {
		"ok": true,
		"path": path,
		"major": major,
		"version_text": first_line,
		"raw": text,
		"error": {},
	}


static func parse_major(text: String) -> int:
	var re := RegEx.new()
	var err := re.compile("version\\s+\"([0-9]+)(?:\\.([0-9]+))?")
	if err != OK:
		return 0
	var m := re.search(text)
	if m == null:
		return 0
	var major := int(m.get_string(1))
	var minor := int(m.get_string(2)) if m.get_string(2) != "" else 0
	if major == 1 and minor > 0:
		return minor
	return major


## 自动查找。required_major 是版本 JSON 要求的最低 Java 大版本（未知按 8）。
## 返回 {ok, path, major, version_text, meets_requirement, error}
static func find_java(required_major: int = 8, preferred_path: String = "", game_root: String = "") -> Dictionary:
	var preferred := FileUtilsScript.normalize(preferred_path)
	if not preferred.is_empty():
		var probed := probe(preferred)
		if not bool(probed.get("ok", false)):
			return probed
		var meets := int(probed.get("major", 0)) >= required_major
		probed["meets_requirement"] = meets
		probed["source"] = "manual"
		if not meets:
			probed["error"] = ErrorInfoScript.make("JAVA_TOO_OLD", {
				"path": preferred,
				"detected": str(probed.get("major", 0)),
				"required": str(required_major),
			})
		return probed
	var candidates := candidate_paths(game_root)
	if candidates.is_empty():
		return {
			"ok": false,
			"error": ErrorInfoScript.make("JAVA_NOT_FOUND", {"hint": install_hint(), "path": suggested_path()}),
		}
	var best: Dictionary = {}
	var best_low: Dictionary = {}
	var probed_count := 0
	for path in candidates:
		if probed_count >= MAX_CANDIDATES:
			break
		probed_count += 1
		var result := probe(path)
		if not bool(result.get("ok", false)):
			continue
		var major := int(result.get("major", 0))
		result["meets_requirement"] = major >= required_major
		result["source"] = "auto"
		if major >= required_major:
			if best.is_empty() or major < int(best.get("major", 0)) or major == required_major:
				best = result
				if major == required_major:
					break
		else:
			if best_low.is_empty() or major > int(best_low.get("major", 0)):
				best_low = result
	if not best.is_empty():
		best["required_major"] = required_major
		best["error"] = {}
		return best
	if not best_low.is_empty():
		best_low["required_major"] = required_major
		best_low["error"] = ErrorInfoScript.make("JAVA_TOO_OLD", {
			"path": str(best_low.get("path", "")),
			"detected": str(best_low.get("major", 0)),
			"required": str(required_major),
		})
		return best_low
	return {
		"ok": false,
		"error": ErrorInfoScript.make("JAVA_NOT_FOUND", {"hint": install_hint(), "path": suggested_path()}),
	}


static func suggested_path() -> String:
	if OS.get_name() == "Windows":
		return "C:/Program Files/Java"
	if OS.get_name() == "macOS":
		return "/Library/Java/JavaVirtualMachines"
	return "/usr/lib/jvm"


static func candidate_paths(game_root: String = "") -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	var exe := "java.exe" if OS.get_name() == "Windows" else "java"

	var java_home := OS.get_environment("JAVA_HOME")
	if not java_home.is_empty():
		_add_candidate(out, seen, java_home.replace("\\", "/") + "/bin/" + exe)

	var path_env := OS.get_environment("PATH")
	if not path_env.is_empty():
		var sep := ";" if OS.get_name() == "Windows" else ":"
		for part in path_env.split(sep, false):
			_add_candidate(out, seen, part.replace("\\", "/") + "/" + exe)

	for root in _common_java_roots():
		for sub in FileUtilsScript.list_dirs(root):
			var base := FileUtilsScript.join(root, sub)
			_add_candidate(out, seen, FileUtilsScript.join(base, "bin/" + exe))
			_add_candidate(out, seen, FileUtilsScript.join(base, "Contents/Home/bin/" + exe))
			for nested in FileUtilsScript.list_dirs(base):
				_add_candidate(out, seen, FileUtilsScript.join(base, nested + "/bin/" + exe))

	# 官方启动器自带的 Java runtime（仅查找，不修改）。
	var appdata := OS.get_environment("APPDATA")
	if not appdata.is_empty():
		_scan_for_java(appdata.replace("\\", "/") + "/.minecraft/runtime", exe, out, seen, 4, [0])
	var selected_root := FileUtilsScript.normalize(game_root)
	if not selected_root.is_empty():
		_scan_for_java(FileUtilsScript.join(selected_root, "runtime"), exe, out, seen, 4, [0])
	return out


static func _common_java_roots() -> PackedStringArray:
	var roots := PackedStringArray()
	if OS.get_name() == "Windows":
		roots.append_array([
			"C:/Program Files/Java",
			"C:/Program Files/Eclipse Adoptium",
			"C:/Program Files/Microsoft",
			"C:/Program Files/Amazon Corretto",
			"C:/Program Files/Zulu",
			"C:/Program Files/BellSoft",
			"C:/Program Files/OpenJDK",
			"C:/Program Files (x86)/Java",
			"C:/Program Files (x86)/Eclipse Adoptium",
		])
		var local := OS.get_environment("LOCALAPPDATA")
		if not local.is_empty():
			roots.append(local.replace("\\", "/") + "/Programs/Eclipse Adoptium")
		var home := OS.get_environment("USERPROFILE")
		if not home.is_empty():
			roots.append(home.replace("\\", "/") + "/.jdks")
	else:
		roots.append_array([
			"/usr/lib/jvm",
			"/usr/java",
			"/opt/java",
			"/Library/Java/JavaVirtualMachines",
		])
		var home2 := OS.get_environment("HOME")
		if not home2.is_empty():
			roots.append(home2 + "/.jdks")
	return roots


static func _add_candidate(out: PackedStringArray, seen: Dictionary, path: String) -> void:
	var p := FileUtilsScript.normalize(path)
	if p.is_empty() or seen.has(p):
		return
	seen[p] = true
	out.append(p)


static func _scan_for_java(root: String, exe: String, out: PackedStringArray, seen: Dictionary, depth: int, budget: Array) -> void:
	if depth < 0 or int(budget[0]) >= MAX_SCAN_ENTRIES:
		return
	if not DirAccess.dir_exists_absolute(root):
		return
	var dir := DirAccess.open(root)
	if dir == null:
		return
	for file in dir.get_files():
		if str(file).to_lower() == exe:
			_add_candidate(out, seen, root + "/" + str(file))
	for sub in dir.get_directories():
		budget[0] = int(budget[0]) + 1
		_scan_for_java(root + "/" + str(sub), exe, out, seen, depth - 1, budget)


static func install_hint() -> String:
	if OS.get_name() == "Windows":
		return "C:/Program Files/Java/<版本>/bin/java.exe\nC:/Program Files/Eclipse Adoptium/<版本>/bin/java.exe\nC:/Program Files/Microsoft/<版本>/bin/java.exe"
	if OS.get_name() == "macOS":
		return "/Library/Java/JavaVirtualMachines/<版本>/Contents/Home/bin/java"
	return "/usr/lib/jvm/<版本>/bin/java\n/usr/bin/java"


static func suggestion_text() -> String:
	return install_hint()
