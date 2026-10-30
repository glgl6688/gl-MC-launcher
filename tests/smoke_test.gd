extends Node
## 无界面冒烟测试：核心逻辑（扫描、配置、Java 解析、启动参数、资源复制、整合包导入）。
## 运行方式（在项目目录）：
##   godot --headless --path . tests/smoke_test.tscn
## 测试只写入系统临时目录与 user://auth，不会修改工作区内的游戏文件。

const FileUtilsScript = preload("res://scripts/core/file_utils.gd")
const ErrorInfoScript = preload("res://scripts/core/error_info.gd")
const InstanceConfigScript = preload("res://scripts/core/instance_config.gd")
const VersionScannerScript = preload("res://scripts/core/version_scanner.gd")
const JavaManagerScript = preload("res://scripts/core/java_manager.gd")
const AuthHelperScript = preload("res://scripts/core/auth_helper.gd")
const LaunchBuilderScript = preload("res://scripts/core/launch_builder.gd")
const VersionResolverScript = preload("res://scripts/core/version_resolver.gd")
const ResourceInstallerScript = preload("res://scripts/core/resource_installer.gd")
const MrpackImporterScript = preload("res://scripts/core/mrpack_importer.gd")
const RuntimePathsScript = preload("res://scripts/core/runtime_paths.gd")

var _failures: Array[String] = []
var _base := ""


func _ready() -> void:
	_base = FileUtilsScript.normalize(OS.get_environment("TEMP")) + "/gl_smoke_%d" % Time.get_ticks_usec()
	FileUtilsScript.ensure_dir(_base)
	ConfigManager.auth_root = "user://smoke_auth_%d" % Time.get_ticks_usec()
	FileUtilsScript.ensure_dir(ConfigManager.auth_dir())
	print("== gl启动器 冒烟测试 ==")
	print("临时目录：", _base)
	_test_error_info()
	_test_file_utils()
	_test_instance_config()
	_test_version_scanner()
	_test_auth()
	_test_pcl_detection()
	_test_java_parse()
	_test_launch_builder()
	_test_resource_installer()
	_test_mrpack_importer()
	_test_inheritance()
	print("")
	if _failures.is_empty():
		print("全部通过")
		get_tree().quit(0)
	else:
		print("失败 %d 项：" % _failures.size())
		for f in _failures:
			print("  - ", f)
		get_tree().quit(1)


func _check(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("PASS  ", name)
	else:
		_failures.append(name + ("" if detail.is_empty() else " :: " + detail))
		print("FAIL  ", name, "  ", detail)


func _test_error_info() -> void:
	var e := ErrorInfoScript.make("NO_VERSIONS_DIR", {"path": "C:/demo/versions"})
	_check("错误对象包含路径", str(e.get("path", "")) == "C:/demo/versions")
	_check("错误文案完成替换", not str(e.get("message", "")).contains("{path}"), str(e.get("message", "")))
	_check("错误对象有修复建议", not str(e.get("fix_hint", "")).is_empty())


func _test_file_utils() -> void:
	var data_dir := RuntimePathsScript.data_dir()
	_check("数据目录不在 AppData", not data_dir.begins_with("user://"), data_dir)
	_check("路径归一化", FileUtilsScript.normalize("C:\\a\\b\\") == "C:/a/b")
	_check("相对路径安全", FileUtilsScript.is_safe_relative("mods/a.jar"))
	_check("拒绝 .. 越界", not FileUtilsScript.is_safe_relative("../evil.txt"))
	_check("拒绝绝对路径", not FileUtilsScript.is_safe_relative("/etc/passwd"))
	_check("拒绝盘符", not FileUtilsScript.is_safe_relative("C:/evil.txt"))
	var src := _base + "/copy/src.bin"
	var dst := _base + "/copy/dst.bin"
	var data := PackedByteArray()
	for i in range(5000):
		data.append(i % 251)
	FileUtilsScript.write_bytes(src, data)
	var result := FileUtilsScript.copy_file_chunked(src, dst)
	_check("分块复制成功", bool(result.get("ok", false)), str(result))
	_check("复制内容一致", FileAccess.get_file_as_bytes(dst) == data)
	var hash := FileUtilsScript.hash_file(dst, HashingContext.HASH_SHA1)
	_check("SHA-1 计算", bool(hash.get("ok", false)) and str(hash.get("hex", "")).length() == 40)


func _test_instance_config() -> void:
	_check("实例名校验通过", InstanceConfigScript.is_valid_name("我的 实例"))
	_check("实例名拒绝斜杠", not InstanceConfigScript.is_valid_name("a/b"))
	_check("实例名拒绝保留名", not InstanceConfigScript.is_valid_name("CON"))
	_check("实例名拒绝 ..", not InstanceConfigScript.is_valid_name(".."))
	_check("实例名清理", InstanceConfigScript.sanitize_name("a:b*c") == "a_b_c")
	var root := _base + "/version_instances/demo"
	var cfg := InstanceConfigScript.create("demo")
	cfg.username = "TestUser"
	cfg.account_mode = "offline"
	_check("版本目录游戏目录", cfg.effective_game_dir("C:/game") == "C:/game/versions/demo")
	var saved: Dictionary = cfg.save_to(root)
	_check("版本目录实例保存", bool(saved.get("ok", false)), str(saved))
	_check("配置在 gl-instance.json", str(saved.get("path", "")).ends_with("/gl-instance.json"), str(saved))
	var loaded := InstanceConfigScript.load_for_version(root, "demo", "C:/game")
	_check("版本目录实例读取", bool(loaded.get("found", false)), str(loaded))
	var cfg2 = loaded.get("config", null)
	_check("实例配置字段", cfg2 != null and cfg2.username == "TestUser" and cfg2.version_id == "demo")
	_check("实例配置路径", str(cfg2.instance_dir).ends_with("/version_instances/demo"))


func _test_version_scanner() -> void:
	var root := _base + "/game"
	var vdir := root + "/versions"
	_write_json(vdir + "/good/good.json", {
		"id": "good", "type": "release", "mainClass": "demo.Main",
		"javaVersion": {"majorVersion": 17},
		"assetIndex": {"id": "1.20"}, "assets": "1.20",
	})
	FileUtilsScript.write_bytes(vdir + "/good/good.jar", PackedByteArray([1, 2, 3]))
	FileUtilsScript.ensure_dir(root + "/assets/indexes")
	FileUtilsScript.write_text(root + "/assets/indexes/1.20.json", "{}")
	FileUtilsScript.write_text(vdir + "/badjson/badjson.json", "{ this is not json")
	FileUtilsScript.write_bytes(vdir + "/badjson/badjson.jar", PackedByteArray([1]))
	_write_json(vdir + "/nojar/nojar.json", {"id": "nojar", "mainClass": "x.Y"})
	FileUtilsScript.ensure_dir(vdir + "/empty")
	FileUtilsScript.ensure_dir(vdir + "/fps/mods")
	for i in range(3):
		FileUtilsScript.write_bytes(vdir + "/fps/mods/mod%d.jar" % i, PackedByteArray([1]))
	_write_json(vdir + "/multi/multi.json", {
		"id": "multi",
		"assetIndex": {"id": "absent-index"},
		"libraries": [{"name": "org.example:missing:1.0"}],
	})
	FileUtilsScript.write_bytes(vdir + "/multi/multi.jar", PackedByteArray([1]))
	var result := VersionScannerScript.scan_sync(root)
	_check("扫描成功", bool(result.get("ok", false)), str(result.get("error", {})))
	var versions: Array = result.get("versions", [])
	_check("扫描数量", versions.size() == 6, str(versions.size()))
	_check("只有一个可用", VersionScannerScript.usable_count(versions) == 1)
	var good := _find_version(versions, "good")
	_check("good 可用", bool(good.get("usable", false)))
	_check("good Java 要求", int(good.get("required_java", 0)) == 17)
	var bad := _find_version(versions, "badjson")
	_check("badjson 不可用", not bool(bad.get("usable", true)))
	_check("badjson 有原因", not str(bad.get("reason", "")).is_empty())
	var nojar := _find_version(versions, "nojar")
	_check("nojar 原因含 JAR", str(nojar.get("reason", "")).contains("JAR"))
	var fps := _find_version(versions, "fps")
	_check("只有 Mod 的文件夹不可用", not bool(fps.get("usable", true)))
	_check("只有 Mod 时提示缺原版", str(fps.get("reason", "")).contains("原版") and str(fps.get("reason", "")).contains("Mod 3"), str(fps.get("reason", "")))
	_check("只有 Mod 时给出操作建议", str(fps.get("fix_hint", "")).contains("安装"), str(fps.get("fix_hint", "")))
	var multi := _find_version(versions, "multi")
	_check("多原因聚合不可用", not bool(multi.get("usable", true)) and (multi.get("issues") as Array).size() >= 3, str(multi.get("issues", [])))
	_check("多原因包含主类", str(multi.get("reason", "")).contains("mainClass"), str(multi.get("reason", "")))
	_check("多原因包含资源索引", str(multi.get("reason", "")).contains("资源索引"), str(multi.get("reason", "")))
	_check("多原因包含运行库", str(multi.get("reason", "")).contains("运行库"), str(multi.get("reason", "")))
	var missing := VersionScannerScript.scan_sync(_base + "/no_such_root")
	_check("缺失版本目录报错", not bool(missing.get("ok", true)))


func _test_auth() -> void:
	_check("离线 UUID TestUser", AuthHelperScript.offline_uuid("TestUser") == "097d3392-865a-3f3c-8b4a-da1c3473466c")
	_check("离线 UUID Player", AuthHelperScript.offline_uuid("Player") == "a01e3843-e521-3998-958a-f459800e4d11")
	var cfg := InstanceConfigScript.create("demo", "auth")
	cfg.username = "TestUser"
	cfg.account_mode = "offline"
	var offline := AuthHelperScript.resolve(cfg)
	_check("离线认证", bool(offline.get("ok", false)) and str(offline.get("uuid", "")) == AuthHelperScript.offline_uuid("TestUser"))
	cfg.username = "bad name"
	_check("用户名拒绝空格", not bool(AuthHelperScript.resolve(cfg).get("ok", true)))
	var token_path := ConfigManager.auth_dir() + "/premium.json"
	FileUtilsScript.write_text(token_path, JSON.stringify({
		"accessToken": "SECRET-TOKEN", "uuid": "11111111-2222-3333-4444-555555555555", "name": "PremiumUser",
	}))
	cfg.username = "PremiumUser"
	cfg.account_mode = "online"
	var online := AuthHelperScript.resolve(cfg)
	_check("正版令牌读取", bool(online.get("ok", false)) and str(online.get("access_token", "")) == "SECRET-TOKEN")
	cfg.account_mode = "thirdparty"
	cfg.auth_url = "https://example.invalid/auth"
	var third_path := ConfigManager.auth_dir() + "/thirdparty.json"
	FileUtilsScript.write_text(third_path, JSON.stringify({
		"accessToken": "SECRET-THIRD", "uuid": "66666666-7777-8888-9999-000000000000", "name": "ThirdUser",
	}))
	var third := AuthHelperScript.resolve(cfg)
	_check("第三方令牌读取", bool(third.get("ok", false)) and str(third.get("access_token", "")) == "SECRET-THIRD")
	var redacted := AuthHelperScript.redacted_argv(PackedStringArray(["--accessToken", "SECRET-TOKEN", "--x"]))
	_check("令牌日志脱敏", redacted[1] == "***" and not ("SECRET-TOKEN" in redacted))
	DirAccess.remove_absolute(token_path)
	DirAccess.remove_absolute(third_path)


func _test_pcl_detection() -> void:
	var game := _base + "/pcl/vallgame/.minecraft"
	var jar := _base + "/pcl/vallgame/mc3331/PCL/authlib-injector.jar"
	FileUtilsScript.write_bytes(jar, PackedByteArray([1]))
	FileUtilsScript.write_text(game + "/versions/demo/PCL/Setup.ini",
		"VersionServerAuthName:LittleSkin 登录\nVersionServerAuthServer:https://littleskin.cn/api/yggdrasil\n")
	var found := AuthHelperScript.find_authlib_jar(game)
	_check("自动查找 PCL authlib-injector", found == jar, found)
	var server := AuthHelperScript.read_pcl_auth_server(game, "demo")
	_check("自动读取 PCL 认证服务器", server == "https://littleskin.cn/api/yggdrasil", server)


func _test_java_parse() -> void:
	_check("解析 Java 17", JavaManagerScript.parse_major('openjdk version "17.0.8" 2023-07-18') == 17)
	_check("解析 Java 8", JavaManagerScript.parse_major('java version "1.8.0_402"') == 8)
	_check("解析 Java 21", JavaManagerScript.parse_major('openjdk version "21" 2023-09-19') == 21)
	_check("解析失败返回 0", JavaManagerScript.parse_major("not a java version") == 0)
	var probe: Dictionary = JavaManagerScript.probe(_base + "/no_java.exe")
	_check("Java 探测失败可读", not bool(probe.get("ok", true)) and not probe.get("error", {}).is_empty())
	var candidates: PackedStringArray = JavaManagerScript.candidate_paths()
	_check("Java 候选路径非空", candidates.size() > 0, str(candidates.size()))
	_check("Java 建议路径可复制", not JavaManagerScript.suggested_path().is_empty())


func _test_launch_builder() -> void:
	var root := _base + "/build"
	_write_json(root + "/versions/demo/demo.json", _demo_version_json(true))
	FileUtilsScript.write_bytes(root + "/versions/demo/demo.jar", PackedByteArray([9, 9, 9]))
	FileUtilsScript.write_bytes(root + "/libraries/org/example/core/1.0/core-1.0.jar", PackedByteArray([1]))
	_write_zip(root + "/libraries/org/example/native/1.0/native-1.0-" + _native_classifier() + ".jar",
		{"native/foo" + _native_suffix(): PackedByteArray([7, 7, 7])})
	FileUtilsScript.write_bytes(root + "/libraries/org/example/native/1.0/native-1.0.jar", PackedByteArray([3]))
	FileUtilsScript.write_text(root + "/assets/indexes/1.20.json", "{}")
	FileUtilsScript.write_text(root + "/assets/log_configs/client.xml", "<xml/>")
	var fake_java := _base + "/fake_java.exe"
	FileUtilsScript.write_bytes(fake_java, PackedByteArray([0]))
	var cfg := InstanceConfigScript.create("demo", "demo-instance")
	cfg.username = "TestUser"
	cfg.account_mode = "offline"
	cfg.isolate = true
	cfg.game_dir_mode = "version"
	cfg.instance_dir = _base + "/build_instances/demo"
	var override := {"ok": true, "path": fake_java, "major": 17, "version_text": "openjdk version \"17.0.8\""}
	var res: Dictionary = LaunchBuilderScript.build("demo", root, cfg.instance_dir, cfg, override)
	_check("启动构建成功", bool(res.get("ok", false)), str(res.get("error", {})))
	var argv: PackedStringArray = res.get("argv", PackedStringArray())
	_check("包含主类", "demo.Main" in argv)
	_check("包含用户名", "--username" in argv and "TestUser" in argv)
	_check("包含离线 UUID", AuthHelperScript.offline_uuid("TestUser") in argv)
	_check("包含 classpath", "-cp" in argv)
	_check("classpath 含运行库", _arg_after(argv, "-cp").contains("core-1.0.jar"))
	_check("classpath 含客户端", _arg_after(argv, "-cp").contains("demo.jar"))
	_check("gameDir 版本文件夹", _arg_after(argv, "--gameDir") == root + "/versions/demo")
	_check("assetIndex", _arg_after(argv, "--assetIndex") == "1.20")
	_check("原生库已解压", FileAccess.file_exists(root + "/versions/demo/gl-natives/foo" + _native_suffix()))
	_check("生成启动预览", not str(res.get("command_preview", "")).is_empty())
	_check("无原生库误报", not str(res.get("warnings", [])).contains("声明了原生库"))
	_check("启动参数不含 user 协议", not str(argv).contains("user://"))
	_check("JVM 编码参数", "-Dfile.encoding=UTF-8" in argv)
	var options_text := str(FileUtilsScript.read_text(root + "/versions/demo/options.txt").get("text", ""))
	_check("自动写入中文设置", options_text.contains("lang:zh_cn") and options_text.contains("forceUnicodeFont:true"))
	var user_cfg = InstanceConfigScript.create("demo", "smoke_user_path")
	user_cfg.username = "TestUser"
	user_cfg.account_mode = "offline"
	user_cfg.instance_dir = "user://smoke_build_%d" % Time.get_ticks_usec()
	var user_res: Dictionary = LaunchBuilderScript.build("demo", root, user_cfg.instance_dir, user_cfg, override)
	_check("user:// 实例构建成功", bool(user_res.get("ok", false)), str(user_res.get("error", {})))
	var user_argv: PackedStringArray = user_res.get("argv", PackedStringArray())
	_check("user:// 已转换为绝对路径", not str(user_argv).contains("user://"))
	_check("gameDir 为绝对路径", _arg_after(user_argv, "--gameDir") == root + "/versions/demo")

	var no_assets := _demo_version_json(false)
	no_assets["assetIndex"] = {"id": "missing-index"}
	_write_json(root + "/versions/noassets/noassets.json", no_assets)
	FileUtilsScript.write_bytes(root + "/versions/noassets/noassets.jar", PackedByteArray([1]))
	var bad: Dictionary = LaunchBuilderScript.build("noassets", root, cfg.instance_dir, cfg, override)
	_check("缺少资源索引被拦截", not bool(bad.get("ok", true)))
	_check("资源索引错误码", str(bad.get("error", {}).get("code", "")) == "ASSET_INDEX_MISSING", str(bad.get("error", {})))

	var old_java := {"ok": true, "path": fake_java, "major": 8, "version_text": "java 1.8", "meets_requirement": false,
		"error": ErrorInfoScript.make("JAVA_TOO_OLD", {"path": fake_java, "detected": "8", "required": "17"})}
	var too_old: Dictionary = LaunchBuilderScript.build("demo", root, cfg.instance_dir, cfg, old_java)
	_check("Java 版本过低被拦截", not bool(too_old.get("ok", true)) and str(too_old.get("error", {}).get("code", "")) == "JAVA_TOO_OLD")

	DirAccess.remove_absolute(root + "/libraries/org/example/core/1.0/core-1.0.jar")
	var missing_lib: Dictionary = LaunchBuilderScript.build("demo", root, cfg.instance_dir, cfg, override)
	_check("缺少运行库被拦截", not bool(missing_lib.get("ok", true)) and str(missing_lib.get("error", {}).get("code", "")) == "LIBRARY_MISSING")

	var authlib_jar := _base + "/authlib-injector.jar"
	FileUtilsScript.write_bytes(authlib_jar, PackedByteArray([1]))
	var third_token := ConfigManager.auth_dir() + "/thirdparty.json"
	FileUtilsScript.write_text(third_token, JSON.stringify({
		"accessToken": "THIRD-TOKEN", "uuid": "77777777-8888-9999-aaaa-bbbbbbbbbbbb",
		"name": "ThirdPlayer", "server": "https://example.invalid/api/yggdrasil",
	}))
	var third_cfg = InstanceConfigScript.create("demo", "third-test")
	third_cfg.username = "ThirdPlayer"
	third_cfg.account_mode = "thirdparty"
	third_cfg.auth_url = "https://example.invalid/api/yggdrasil"
	third_cfg.authlib_jar = authlib_jar
	third_cfg.instance_dir = _base + "/third_instances/demo"
	FileUtilsScript.write_bytes(root + "/libraries/org/example/core/1.0/core-1.0.jar", PackedByteArray([1]))
	var third_res: Dictionary = LaunchBuilderScript.build("demo", root, third_cfg.instance_dir, third_cfg, override)
	_check("第三方启动构建成功", bool(third_res.get("ok", false)), str(third_res.get("error", {})))
	var third_argv: PackedStringArray = third_res.get("argv", PackedStringArray())
	_check("注入 authlib-injector", str(third_argv).contains("-javaagent:" + authlib_jar + "=https://example.invalid/api/yggdrasil"))
	_check("第三方 userType", _arg_after(third_argv, "--userType") == "mojang")
	DirAccess.remove_absolute(third_token)

	var premium_token := ConfigManager.auth_dir() + "/premium.json"
	FileUtilsScript.write_text(premium_token, JSON.stringify({
		"accessToken": "MS-TOKEN", "uuid": "99999999-8888-7777-6666-555555555555",
		"name": "MsPlayer", "refreshToken": "MS-REFRESH", "clientId": "test-client",
	}))
	var ms_cfg = InstanceConfigScript.create("demo", "ms-test")
	ms_cfg.username = "MsPlayer"
	ms_cfg.account_mode = "online"
	ms_cfg.instance_dir = _base + "/ms_instances/demo"
	FileUtilsScript.write_bytes(root + "/libraries/org/example/core/1.0/core-1.0.jar", PackedByteArray([1]))
	var ms_res: Dictionary = LaunchBuilderScript.build("demo", root, ms_cfg.instance_dir, ms_cfg, override)
	_check("正版启动构建成功", bool(ms_res.get("ok", false)), str(ms_res.get("error", {})))
	var ms_argv: PackedStringArray = ms_res.get("argv", PackedStringArray())
	_check("正版 userType", _arg_after(ms_argv, "--userType") == "msa")
	_check("正版 accessToken", _arg_after(ms_argv, "--accessToken") == "MS-TOKEN")
	DirAccess.remove_absolute(premium_token)


func _test_resource_installer() -> void:
	var game := _base + "/res_game"
	FileUtilsScript.write_bytes(game + "/mods/existing.jar", "OLD".to_utf8_buffer())
	var src := _base + "/res_src/existing.jar"
	FileUtilsScript.write_bytes(src, "NEW".to_utf8_buffer())
	var res := ResourceInstallerScript.install_sync(PackedStringArray([src]), "mod", game)
	_check("Mod 复制成功", bool(res.get("ok", false)), str(res.get("errors", [])))
	_check("Mod 内容更新", FileAccess.get_file_as_bytes(game + "/mods/existing.jar") == "NEW".to_utf8_buffer())
	_check("同名备份 .bak", FileAccess.file_exists(game + "/mods/existing.jar.bak"))
	var self_install := ResourceInstallerScript.install_sync(PackedStringArray([game + "/mods/existing.jar"]), "mod", game)
	_check("同路径安装不破坏文件", bool(self_install.get("ok", false)) and (self_install.get("unchanged", []) as Array).size() == 1 and FileAccess.file_exists(game + "/mods/existing.jar"))
	var bad_src := _base + "/res_src/bad.jar"
	FileUtilsScript.write_bytes(bad_src, "ZIP".to_utf8_buffer())
	var bad := ResourceInstallerScript.install_sync(PackedStringArray([bad_src]), "shader", game)
	_check("错误扩展名被拒绝", not bool(bad.get("ok", true)) and (bad.get("errors", []) as Array).size() > 0)


func _test_mrpack_importer() -> void:
	var pack := _base + "/packs/demo.mrpack"
	var mod_data := "MODDATA".to_utf8_buffer()
	FileUtilsScript.write_bytes(_base + "/mr_src/mods/local.jar", mod_data)
	var sha1 := str(FileUtilsScript.hash_file(_base + "/mr_src/mods/local.jar", HashingContext.HASH_SHA1).get("hex", ""))
	var index := {
		"formatVersion": 1,
		"name": "Demo Pack",
		"versionId": "1.0.0",
		"dependencies": {"minecraft": "1.20.1", "fabric-loader": "0.15.0"},
		"files": [
			{"path": "mods/local.jar", "hashes": {"sha1": sha1}, "fileSize": mod_data.size(), "downloads": ["https://example.invalid/local.jar"], "env": {"client": "required", "server": "required"}},
			{"path": "mods/missing.jar", "hashes": {"sha1": "0000"}, "fileSize": 10, "downloads": ["https://example.invalid/missing.jar"], "env": {"client": "required"}},
			{"path": "mods/serveronly.jar", "hashes": {}, "env": {"client": "unsupported"}},
		],
	}
	_write_zip(pack, {
		"modrinth.index.json": JSON.stringify(index).to_utf8_buffer(),
		"overrides/config/test.txt": "PACK-CONFIG".to_utf8_buffer(),
		"client-overrides/mods/pack.jar": "PACKMOD".to_utf8_buffer(),
	})
	var target := _base + "/mr_target/inst"
	InstanceConfigScript.ensure_layout(target)
	FileUtilsScript.write_text(target + "/.minecraft/config/test.txt", "OLD-CONFIG")
	var result := MrpackImporterScript.import_sync(pack, target + "/.minecraft", _base + "/mr_src")
	_check("整合包导入成功", bool(result.get("ok", false)), str(result.get("error", {})))
	_check("overrides 覆盖 + 备份", FileAccess.get_file_as_bytes(target + "/.minecraft/config/test.txt") == "PACK-CONFIG".to_utf8_buffer() and FileAccess.file_exists(target + "/.minecraft/config/test.txt.bak"))
	_check("client-overrides 复制", FileAccess.file_exists(target + "/.minecraft/mods/pack.jar"))
	_check("files 本地复制", FileAccess.get_file_as_bytes(target + "/.minecraft/mods/local.jar") == mod_data)
	_check("缺失文件被记录", (result.get("missing", []) as Array).size() == 1, str(result.get("missing", [])))
	_check("server-only 跳过", not FileAccess.file_exists(target + "/.minecraft/mods/serveronly.jar"))
	_check("整合包名称解析", str(result.get("name", "")) == "Demo Pack")
	_check("整合包版本解析", str(result.get("minecraft", "")) == "1.20.1")


func _test_inheritance() -> void:
	var root := _base + "/inherit"
	_write_json(root + "/versions/parent/parent.json", {
		"id": "parent", "mainClass": "parent.Main", "assets": "1.20",
		"assetIndex": {"id": "1.20"}, "javaVersion": {"majorVersion": 17},
		"libraries": [{"name": "org.example:parentlib:1.0", "downloads": {"artifact": {"path": "org/example/parentlib/1.0/parentlib-1.0.jar"}}}],
		"arguments": {"game": ["--username", "${auth_player_name}"]},
	})
	FileUtilsScript.write_bytes(root + "/versions/parent/parent.jar", PackedByteArray([1]))
	FileUtilsScript.write_bytes(root + "/libraries/org/example/parentlib/1.0/parentlib-1.0.jar", PackedByteArray([1]))
	_write_json(root + "/versions/child/child.json", {
		"id": "child", "inheritsFrom": "parent", "mainClass": "child.Main",
		"libraries": [{"name": "org.example:parentlib:2.0", "downloads": {"artifact": {"path": "org/example/parentlib/2.0/parentlib-2.0.jar"}}}],
	})
	FileUtilsScript.write_bytes(root + "/libraries/org/example/parentlib/2.0/parentlib-2.0.jar", PackedByteArray([2]))
	FileUtilsScript.write_bytes(root + "/versions/child/child.jar", PackedByteArray([2]))
	FileUtilsScript.write_text(root + "/assets/indexes/1.20.json", "{}")
	var merged := VersionResolverScript.load_merged(root, "child")
	_check("继承链合并成功", bool(merged.get("ok", false)), str(merged.get("error", {})))
	var data: Dictionary = merged.get("json", {})
	_check("子版本覆盖 mainClass", str(data.get("mainClass", "")) == "child.Main")
	_check("继承父版本资源", str(data.get("assets", "")) == "1.20")
	_check("继承父版本运行库", (data.get("libraries", []) as Array).size() == 1)
	var merged_libs: Array = data.get("libraries", [])
	_check("同 artifact 子版本覆盖父版本", str(merged_libs[0].get("name", "")) == "org.example:parentlib:2.0", str(merged_libs))
	var scanned := VersionScannerScript.scan_sync(root)
	var child_entry := _find_version(scanned.get("versions", []), "child")
	_check("扫描器合并继承 Java 要求", int(child_entry.get("required_java", 0)) == 17, str(child_entry.get("required_java", 0)))


func _demo_version_json(with_assets: bool) -> Dictionary:
	var classifier := _native_classifier()
	var classifiers := {}
	classifiers[classifier] = {"path": "org/example/native/1.0/native-1.0-" + classifier + ".jar"}
	var natives := {}
	natives[_os_key()] = classifier
	var native_lib := {
		"name": "org.example:native:1.0",
		"downloads": {
			"artifact": {"path": "org/example/native/1.0/native-1.0.jar"},
			"classifiers": classifiers,
		},
		"natives": natives,
	}
	var data := {
		"id": "demo", "type": "release", "mainClass": "demo.Main",
		"javaVersion": {"majorVersion": 17},
		"libraries": [
			{"name": "org.example:core:1.0", "downloads": {"artifact": {"path": "org/example/core/1.0/core-1.0.jar"}}},
			native_lib,
		],
		"arguments": {
			"game": ["--username", "${auth_player_name}", "--version", "${version_name}", "--gameDir", "${game_directory}",
				"--uuid", "${auth_uuid}", "--accessToken", "${auth_access_token}", "--userType", "${user_type}",
				"--versionType", "${version_type}"],
			"jvm": ["-Djava.library.path=${natives_directory}", "-cp", "${classpath}"],
		},
	}
	if with_assets:
		data["assets"] = "1.20"
		data["assetIndex"] = {"id": "1.20"}
		data["arguments"]["game"].append_array(["--assetsDir", "${assets_root}", "--assetIndex", "${assets_index_name}"])
	return data


func _write_json(path: String, data: Dictionary) -> void:
	FileUtilsScript.write_text(path, JSON.stringify(data, "\t"))


func _write_zip(path: String, entries: Dictionary) -> void:
	FileUtilsScript.ensure_dir(FileUtilsScript.normalize(path).get_base_dir())
	var packer := ZIPPacker.new()
	var err := packer.open(path)
	if err != OK:
		_failures.append("无法创建 ZIP：" + path)
		return
	for name in entries.keys():
		packer.start_file(str(name))
		packer.write_file(entries[name])
		packer.close_file()
	packer.close()


func _find_version(versions: Array, id: String) -> Dictionary:
	for v in versions:
		if str(v.get("id", "")) == id:
			return v
	return {}


func _arg_after(argv: PackedStringArray, flag: String) -> String:
	for i in range(argv.size() - 1):
		if argv[i] == flag:
			return argv[i + 1]
	return ""


func _native_suffix() -> String:
	if OS.get_name() == "Windows":
		return ".dll"
	if OS.get_name() == "macOS":
		return ".dylib"
	return ".so"


func _os_key() -> String:
	if OS.get_name() == "Windows":
		return "windows"
	if OS.get_name() == "macOS":
		return "osx"
	return "linux"


func _native_classifier() -> String:
	return "natives-" + _os_key()
