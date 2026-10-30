class_name LaunchBuilder
extends RefCounted
## 启动命令构建：解析版本 JSON、准备 Java/账户/运行库/资源目录，
## 组装 JVM 参数与游戏参数。整个过程不启动进程，可安全放在后台线程。

const FileUtilsScript = preload("res://scripts/core/file_utils.gd")
const ErrorInfoScript = preload("res://scripts/core/error_info.gd")
const VersionResolverScript = preload("res://scripts/core/version_resolver.gd")
const JavaManagerScript = preload("res://scripts/core/java_manager.gd")
const AuthHelperScript = preload("res://scripts/core/auth_helper.gd")
const InstanceConfigScript = preload("res://scripts/core/instance_config.gd")
const GameOptionsScript = preload("res://scripts/core/game_options.gd")

const LAUNCHER_NAME := "gl-launcher"
const LAUNCHER_VERSION := "1.0.0"


## java_override 仅用于自动化测试/已检测结果注入；正常启动传空字典。
static func build(version_id: String, source_root: String, version_dir: String, cfg, java_override: Dictionary = {}) -> Dictionary:
	var warnings: Array[String] = []
	# 关键：传给 Java 的 --gameDir、classpath、natives、assets 必须是操作系统绝对路径，
	# 不能是 user://。Godot 自己的文件 API 才使用 user://。
	var source := _absolute(source_root)
	var inst := _absolute(version_dir)
	if source.is_empty() or inst.is_empty():
		return _err(ErrorInfoScript.make("LAUNCH_CONFIG_INVALID", {
			"name": version_id,
			"reason": "游戏根目录或实例目录为空",
		}), warnings)
	var loaded := VersionResolverScript.load_merged(source, version_id)
	if not bool(loaded.get("ok", false)):
		return _err(loaded.get("error", ErrorInfoScript.make("UNKNOWN", {"detail": "版本读取失败"})), warnings)
	var data: Dictionary = loaded.get("json", {})
	var jar_path := str(loaded.get("jar_path", ""))
	var version_json_path := FileUtilsScript.join(source, "versions/" + version_id + "/" + version_id + ".json")
	var main_class := str(data.get("mainClass", ""))
	if main_class.is_empty():
		return _err(ErrorInfoScript.make("VERSION_MAIN_CLASS_MISSING", {
			"name": version_id,
			"path": version_json_path,
		}), warnings)
	if not FileAccess.file_exists(jar_path):
		return _err(ErrorInfoScript.make("VERSION_JAR_MISSING", {
			"name": version_id,
			"path": jar_path,
		}), warnings)

	var required_java := VersionResolverScript.required_java(data)
	if not (data.get("javaVersion", {}) is Dictionary):
		warnings.append("版本 JSON 未声明 Java 版本要求，按 Java 8 处理。")

	var java := java_override
	if java.is_empty():
		java = _find_java(cfg, required_java, source)
	if not bool(java.get("ok", false)):
		return _err(java.get("error", ErrorInfoScript.make("JAVA_NOT_FOUND", {"hint": JavaManagerScript.install_hint()})), warnings)
	if not bool(java.get("meets_requirement", true)):
		var java_err: Variant = java.get("error", {})
		if not (java_err is Dictionary) or java_err.is_empty():
			java_err = ErrorInfoScript.make("JAVA_TOO_OLD", {
				"path": str(java.get("path", "")),
				"detected": str(java.get("major", 0)),
				"required": str(required_java),
			})
		return _err(java_err, warnings)
	var java_path := str(java.get("path", ""))
	if java_path.is_empty() or not FileAccess.file_exists(java_path):
		return _err(ErrorInfoScript.make("JAVA_NOT_FOUND", {"hint": JavaManagerScript.install_hint()}), warnings)

	var auth := AuthHelperScript.resolve(cfg)
	if not bool(auth.get("ok", false)):
		return _err(auth.get("error", ErrorInfoScript.make("ACCOUNT_INVALID", {"reason": "账户信息无效"})), warnings)

	var extra_jvm: Array[String] = []
	if str(cfg.account_mode) == "thirdparty":
		var authlib_path := _absolute(str(cfg.authlib_jar))
		if authlib_path.is_empty() or not FileAccess.file_exists(authlib_path):
			return _err(ErrorInfoScript.make("AUTH_INJECTOR_REQUIRED", {
				"path": authlib_path if not authlib_path.is_empty() else "（未选择）",
			}), warnings)
		var server := str(auth.get("server", cfg.auth_url)).strip_edges()
		if server.is_empty():
			return _err(ErrorInfoScript.make("AUTH_SERVER_REQUIRED", {"path": ""}), warnings)
		var agent_arg := "-javaagent:" + authlib_path
		if not server.is_empty():
			agent_arg += "=" + server
		extra_jvm.append(agent_arg)

	var game_dir := FileUtilsScript.join(source, "versions/" + version_id)
	InstanceConfigScript.ensure_game_dirs(game_dir)
	FileUtilsScript.ensure_dir(game_dir)
	if bool(cfg.auto_chinese):
		var options_result := GameOptionsScript.ensure_chinese(game_dir, source)
		if not bool(options_result.get("ok", false)):
			warnings.append("无法写入中文游戏设置：" + str(options_result.get("error", "")))

	var assets_root := FileUtilsScript.join(source, "assets")
	var library_dir := FileUtilsScript.join(source, "libraries")
	var natives_dir := FileUtilsScript.join(game_dir, "gl-natives")
	var asset_id := VersionResolverScript.asset_index_id(data)
	if not asset_id.is_empty():
		var index_path := FileUtilsScript.join(assets_root, "indexes/" + asset_id + ".json")
		if not FileAccess.file_exists(index_path):
			return _err(ErrorInfoScript.make("ASSET_INDEX_MISSING", {"path": index_path}), warnings)

	var libs: Array = data.get("libraries", []) if data.get("libraries", []) is Array else []
	var classpath_parts: Array[String] = []
	var missing: Array[String] = []
	for lib in libs:
		if not (lib is Dictionary):
			continue
		if not VersionResolverScript.library_allowed(lib):
			continue
		var artifact := VersionResolverScript.artifact_path(source, lib)
		if artifact.is_empty() or not FileAccess.file_exists(artifact):
			missing.append(str(lib.get("name", "?")) + " -> " + artifact)
		elif not classpath_parts.has(artifact):
			classpath_parts.append(artifact)
		var classifier := VersionResolverScript.native_classifier(lib)
		if not classifier.is_empty():
			var native_jar := VersionResolverScript.native_path(source, lib, classifier)
			if native_jar.is_empty() or not FileAccess.file_exists(native_jar):
				missing.append(str(lib.get("name", "?")) + " (natives) -> " + native_jar)
	if not missing.is_empty():
		var detail: Array[String] = []
		for i in range(mini(8, missing.size())):
			detail.append("- " + missing[i])
		if missing.size() > 8:
			detail.append("- ……另有 %d 个" % (missing.size() - 8))
		return _err(ErrorInfoScript.make("LIBRARY_MISSING", {
			"count": str(missing.size()),
			"detail": "\n".join(detail),
			"path": library_dir,
		}), warnings)
	classpath_parts.append(jar_path)
	var classpath := ":".join(classpath_parts) if OS.get_name() != "Windows" else ";".join(classpath_parts)
	if classpath_parts.size() <= 1:
		warnings.append("该版本没有声明运行库，仅使用客户端 JAR。")

	var native_result := VersionResolverScript.extract_natives_from(source, libs, natives_dir, warnings)
	if not bool(native_result.get("ok", false)):
		return _err(native_result.get("error", ErrorInfoScript.make("NATIVES_EXTRACT_FAILED", {"path": natives_dir, "reason": "未知"})), warnings)

	var sep := ";" if OS.get_name() == "Windows" else ":"
	var vars := {
		"auth_player_name": str(auth.get("username", "")),
		"version_name": version_id,
		"game_directory": game_dir,
		"assets_root": assets_root,
		"game_assets": assets_root,
		"assets_index_name": asset_id,
		"auth_uuid": str(auth.get("uuid", "")),
		"auth_access_token": str(auth.get("access_token", "")),
		"auth_session": "token:%s:%s" % [str(auth.get("access_token", "")), str(auth.get("uuid", ""))],
		"user_type": str(auth.get("user_type", "legacy")),
		"version_type": str(data.get("type", "release")),
		"user_properties": "{}",
		"natives_directory": natives_dir,
		"classpath": classpath,
		"classpath_separator": sep,
		"library_directory": library_dir,
		"launcher_name": LAUNCHER_NAME,
		"launcher_version": LAUNCHER_VERSION,
		"clientid": "",
		"auth_xuid": "",
	}

	var jvm_args := _build_jvm_args(data, vars, natives_dir, classpath, assets_root, cfg, extra_jvm, warnings)
	var game_args := _build_game_args(data, vars, warnings)
	if game_args.is_empty():
		warnings.append("版本 JSON 没有可用的游戏参数，已使用基础参数。")
		game_args = _default_game_args(version_id, vars)

	var argv := PackedStringArray()
	for arg in jvm_args:
		argv.append(arg)
	argv.append(main_class)
	for arg in game_args:
		argv.append(arg)

	var log_path := FileUtilsScript.join(game_dir, "logs/latest.log")
	return {
		"ok": true,
		"error": {},
		"warnings": warnings,
		"java_path": java_path,
		"java_major": int(java.get("major", 0)),
		"java_version_text": str(java.get("version_text", "")),
		"argv": argv,
		"game_dir": game_dir,
		"instance_dir": game_dir,
		"version_id": version_id,
		"main_class": main_class,
		"required_java": required_java,
		"classpath": classpath,
		"natives_dir": natives_dir,
		"log_path": log_path,
		"command_preview": AuthHelperScript.command_preview(java_path, argv),
	}


static func _find_java(cfg, required: int, game_root: String) -> Dictionary:
	if str(cfg.java_mode) == "manual":
		var manual := str(cfg.java_path)
		if manual.strip_edges().is_empty():
			return {
				"ok": false,
				"error": ErrorInfoScript.make("JAVA_NOT_FOUND", {"hint": JavaManagerScript.install_hint(), "path": JavaManagerScript.suggested_path()}),
			}
		return JavaManagerScript.find_java(required, manual, game_root)
	return JavaManagerScript.find_java(required, "", game_root)


static func _build_jvm_args(data: Dictionary, vars: Dictionary, natives_dir: String, classpath: String, assets_root: String, cfg, extra_jvm: Array[String], warnings: Array) -> Array[String]:
	var out: Array[String] = []
	var memory := clampi(int(cfg.max_memory_mb), 512, 32768)
	out.append("-Xmx%dM" % memory)
	out.append("-Xms%dM" % mini(512, memory))
	out.append("-Dlog4j2.formatMsgNoLookups=true")
	out.append("-Dfile.encoding=UTF-8")
	out.append("-Dminecraft.launcher.brand=" + LAUNCHER_NAME)
	out.append("-Dminecraft.launcher.version=" + LAUNCHER_VERSION)
	for arg in extra_jvm:
		out.append(arg)

	var official: Array = []
	var arguments: Variant = data.get("arguments", {})
	if arguments is Dictionary and arguments.get("jvm", []) is Array:
		official = arguments.get("jvm", [])
	var has_classpath := false
	var has_library_path := false
	if not official.is_empty():
		var collected := _collect_args(official, vars, warnings)
		for arg in collected:
			if arg == "-cp" or arg == "-classpath" or arg == "--class-path":
				has_classpath = true
			if arg.begins_with("-Djava.library.path"):
				has_library_path = true
		out.append_array(collected)
	if not has_library_path:
		out.append("-Djava.library.path=" + natives_dir)
	if not has_classpath:
		out.append("-cp")
		out.append(classpath)

	var logging: Variant = data.get("logging", {})
	if logging is Dictionary and logging.get("client", {}) is Dictionary:
		var client: Dictionary = logging.get("client", {})
		var argument := str(client.get("argument", ""))
		var file_info: Variant = client.get("file", {})
		var file_id := ""
		if file_info is Dictionary:
			file_id = str(file_info.get("id", ""))
		var log_config := FileUtilsScript.join(assets_root, "log_configs/" + file_id)
		if not argument.is_empty() and not file_id.is_empty() and FileAccess.file_exists(log_config):
			out.append(argument.replace("${path}", log_config))
		elif not argument.is_empty():
			warnings.append("没有找到日志配置文件，已跳过日志参数：" + log_config)
	return out


static func _build_game_args(data: Dictionary, vars: Dictionary, warnings: Array) -> Array[String]:
	var arguments: Variant = data.get("arguments", {})
	if arguments is Dictionary and arguments.get("game", []) is Array and not arguments.get("game", []).is_empty():
		return _collect_args(arguments.get("game", []), vars, warnings)
	var legacy := str(data.get("minecraftArguments", "")).strip_edges()
	if not legacy.is_empty():
		return _collect_args(legacy.split(" ", false), vars, warnings)
	return []


static func _collect_args(entries: Array, vars: Dictionary, warnings: Array) -> Array[String]:
	var out: Array[String] = []
	for entry in entries:
		if entry is String:
			out.append(_substitute(entry, vars, warnings))
		elif entry is Dictionary:
			var rules: Array = entry.get("rules", []) if entry.get("rules", []) is Array else []
			if not rules.is_empty() and not VersionResolverScript.rules_allow(rules):
				continue
			var value: Variant = entry.get("value", "")
			if value is String:
				out.append(_substitute(value, vars, warnings))
			elif value is Array:
				for item in value:
					out.append(_substitute(str(item), vars, warnings))
	return out


static func _substitute(text: String, vars: Dictionary, warnings: Array) -> String:
	var result := text
	for key in vars.keys():
		var token := "${" + str(key) + "}"
		if result.contains(token):
			result = result.replace(token, str(vars[key]))
	if result.contains("${"):
		warnings.append("存在未识别的启动变量，已原样保留：" + result)
	return result


static func _default_game_args(version_id: String, vars: Dictionary) -> Array[String]:
	var out: Array[String] = [
		"--username", str(vars.get("auth_player_name", "")),
		"--version", version_id,
		"--gameDir", str(vars.get("game_directory", "")),
		"--uuid", str(vars.get("auth_uuid", "")),
		"--accessToken", str(vars.get("auth_access_token", "")),
		"--userType", str(vars.get("user_type", "legacy")),
		"--versionType", str(vars.get("version_type", "release")),
	]
	var asset_id := str(vars.get("assets_index_name", ""))
	if not asset_id.is_empty():
		out.append_array([
			"--assetsDir", str(vars.get("assets_root", "")),
			"--assetIndex", asset_id,
		])
	return out


static func _absolute(path: String) -> String:
	var p := FileUtilsScript.normalize(path)
	if p.begins_with("user://") or p.begins_with("res://"):
		return ProjectSettings.globalize_path(p).replace("\\", "/")
	return p


static func _err(error: Dictionary, warnings: Array) -> Dictionary:
	return {
		"ok": false,
		"error": error,
		"warnings": warnings,
		"java_path": "",
		"argv": PackedStringArray(),
		"game_dir": "",
		"log_path": "",
		"command_preview": "",
	}
