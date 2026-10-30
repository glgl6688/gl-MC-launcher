class_name VersionDiagnostics
extends RefCounted
## 启动前诊断：不只检查 JSON/JAR，还检查主类、资源索引、运行库与 natives。
## 返回多个问题，UI 可以一次性告诉玩家“到底缺什么”。

const FileUtilsScript = preload("res://scripts/core/file_utils.gd")
const VersionResolverScript = preload("res://scripts/core/version_resolver.gd")


static func inspect(source_root: String, version_id: String, version_dir: String) -> Dictionary:
	var issues: Array[Dictionary] = []
	var loaded := VersionResolverScript.load_merged(source_root, version_id)
	if not bool(loaded.get("ok", false)):
		var err: Dictionary = loaded.get("error", {})
		issues.append({
			"code": str(err.get("code", "VERSION_INVALID")),
			"reason": str(err.get("message", "版本描述读取失败")),
			"fix": str(err.get("fix_hint", "请补全该版本的 JSON 与运行库。")),
		})
	else:
		var data: Dictionary = loaded.get("json", {})
		var main_class := str(data.get("mainClass", ""))
		if main_class.is_empty():
			issues.append({
				"code": "VERSION_MAIN_CLASS_MISSING",
				"reason": "版本 JSON 没有 mainClass，无法确定启动主类",
				"fix": "请用完整版本 JSON 补全，或重新安装 Fabric/Forge 版本。",
			})
		var jar_path := str(loaded.get("jar_path", ""))
		if jar_path.is_empty() or not FileAccess.file_exists(jar_path):
			issues.append({
				"code": "VERSION_JAR_MISSING",
				"reason": "缺少客户端 JAR：" + jar_path,
				"fix": "请补上原版客户端 JAR，或重新安装该版本；只有 Mod 不能启动。",
			})
		var assets_root := FileUtilsScript.join(source_root, "assets")
		var asset_id := VersionResolverScript.asset_index_id(data)
		if not asset_id.is_empty():
			var index_path := FileUtilsScript.join(assets_root, "indexes/" + asset_id + ".json")
			if not FileAccess.file_exists(index_path):
				issues.append({
					"code": "ASSET_INDEX_MISSING",
					"reason": "缺少资源索引：" + index_path,
					"fix": "请用本地完整 assets/indexes 补全，或重新安装该版本。",
				})
		var libs: Array = data.get("libraries", []) if data.get("libraries", []) is Array else []
		var missing_libs: Array[String] = []
		for lib in libs:
			if not (lib is Dictionary):
				continue
			if not VersionResolverScript.library_allowed(lib):
				continue
			var artifact := VersionResolverScript.artifact_path(source_root, lib)
			if artifact.is_empty() or not FileAccess.file_exists(artifact):
				missing_libs.append(str(lib.get("name", "?")))
			var classifier := VersionResolverScript.native_classifier(lib)
			if not classifier.is_empty():
				var native := VersionResolverScript.native_path(source_root, lib, classifier)
				if native.is_empty() or not FileAccess.file_exists(native):
					missing_libs.append(str(lib.get("name", "?")) + " (natives)")
		if not missing_libs.is_empty():
			var example := ""
			for i in range(mini(3, missing_libs.size())):
				example += ("；" if not example.is_empty() else "") + missing_libs[i]
			issues.append({
				"code": "LIBRARY_MISSING",
				"reason": "缺少 %d 个运行库：%s" % [missing_libs.size(), example],
				"fix": "请用本地完整 libraries 目录补全（启动器不下载运行库）；确认版本 JSON 要求的库都存在。",
			})
	if issues.is_empty():
		return {"ok": true, "issues": [], "reason": "", "fix_hint": "", "error_code": ""}
	var reasons: Array[String] = []
	var fixes: Array[String] = []
	for issue in issues:
		reasons.append(str(issue.get("reason", "")))
		var f := str(issue.get("fix", ""))
		if not f.is_empty() and not fixes.has(f):
			fixes.append(f)
	return {
		"ok": false,
		"issues": issues,
		"reason": "\n".join(reasons),
		"fix_hint": "\n".join(fixes),
		"error_code": str(issues[0].get("code", "VERSION_INVALID")),
	}
