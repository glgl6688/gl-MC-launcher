class_name AuthHelper
extends RefCounted
## 账户模式解析。正版读取本地令牌；第三方令牌由 OnlineAuth 登录后写入，本文件只负责读取。
## 离线 UUID 使用 OfflinePlayer 算法（MD5 后设置 version=3、variant 位）。

const FileUtilsScript = preload("res://scripts/core/file_utils.gd")
const ErrorInfoScript = preload("res://scripts/core/error_info.gd")

const PREMIUM_TOKEN_NAME := "premium.json"
const THIRDPARTY_TOKEN_NAME := "thirdparty.json"


static func offline_uuid(username: String) -> String:
	var ctx := HashingContext.new()
	var start_err := ctx.start(HashingContext.HASH_MD5)
	if start_err != OK:
		return "00000000-0000-0000-0000-000000000000"
	ctx.update(("OfflinePlayer:" + username).to_utf8_buffer())
	var digest := ctx.finish()
	if digest.size() != 16:
		return "00000000-0000-0000-0000-000000000000"
	digest[6] = (digest[6] & 0x0f) | 0x30
	digest[8] = (digest[8] & 0x3f) | 0x80
	var hex := digest.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8),
		hex.substr(8, 4),
		hex.substr(12, 4),
		hex.substr(16, 4),
		hex.substr(20, 12),
	]


## 返回 {ok, username, uuid, access_token, user_type, token_path, error}
static func resolve(cfg) -> Dictionary:
	var username := str(cfg.username).strip_edges()
	if username.is_empty():
		return _fail("ACCOUNT_INVALID", {"reason": "用户名为空"})
	if username.length() > 16:
		return _fail("ACCOUNT_INVALID", {"reason": "用户名超过 16 个字符"})
	if username.contains(" ") or username.contains("\t") or username.contains("\n"):
		return _fail("ACCOUNT_INVALID", {"reason": "用户名不能包含空白字符"})
	if cfg.account_mode == "offline":
		return {
			"ok": true,
			"username": username,
			"uuid": offline_uuid(username),
			"access_token": "0",
			"user_type": "legacy",
			"token_path": "",
			"server": "",
			"error": {},
		}
	var token_name := PREMIUM_TOKEN_NAME if cfg.account_mode == "online" else THIRDPARTY_TOKEN_NAME
	var token_path := ConfigManager.auth_dir() + "/" + token_name
	var global_path := ProjectSettings.globalize_path(token_path).replace("\\", "/")
	if not FileAccess.file_exists(token_path):
		return _fail("TOKEN_MISSING", {
			"path": global_path,
			"reason": "文件不存在",
		})
	var f := FileAccess.open(token_path, FileAccess.READ)
	if f == null:
		return _fail("TOKEN_MISSING", {
			"path": global_path,
			"reason": error_string(FileAccess.get_open_error()),
		})
	var text := f.get_as_text()
	f.close()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return _fail("TOKEN_MISSING", {
			"path": global_path,
			"reason": "JSON 解析失败：第 %d 行 %s" % [parser.get_error_line(), parser.get_error_message()],
		})
	if not (parser.data is Dictionary):
		return _fail("TOKEN_MISSING", {"path": global_path, "reason": "JSON 根节点不是对象"})
	var data: Dictionary = parser.data
	var token := str(data.get("accessToken", data.get("access_token", "")))
	var uuid := str(data.get("uuid", data.get("id", "")))
	var name := str(data.get("name", username))
	var server := str(data.get("server", cfg.auth_url))
	if token.is_empty() or uuid.is_empty():
		return _fail("TOKEN_MISSING", {
			"path": global_path,
			"reason": "缺少 accessToken 或 uuid 字段",
		})
	return {
		"ok": true,
		"username": name if not name.is_empty() else username,
		"uuid": uuid,
		"access_token": token,
		"user_type": "msa" if cfg.account_mode == "online" else "mojang",
		"token_path": global_path,
		"server": server,
		"error": {},
	}


## 在游戏根目录及其同级目录中查找 PCL 常用的 authlib-injector.jar。
static func find_authlib_jar(game_root: String) -> String:
	var root := FileUtilsScript.normalize(game_root)
	if root.is_empty():
		return ""
	var candidates: Array[String] = [
		FileUtilsScript.join(root, "authlib-injector.jar"),
		FileUtilsScript.join(root, "PCL/authlib-injector.jar"),
	]
	var parent := root.get_base_dir()
	candidates.append(FileUtilsScript.join(parent, "PCL/authlib-injector.jar"))
	for name in FileUtilsScript.list_dirs(parent):
		var sibling := FileUtilsScript.join(parent, name)
		candidates.append(FileUtilsScript.join(sibling, "authlib-injector.jar"))
		candidates.append(FileUtilsScript.join(sibling, "PCL/authlib-injector.jar"))
	for path in candidates:
		if FileAccess.file_exists(path):
			return path
	return ""


## 读取 PCL 在 versions/<id>/PCL/Setup.ini 中记录的认证服务器。
static func read_pcl_auth_server(game_root: String, version_id: String) -> String:
	var path := FileUtilsScript.join(game_root, "versions/" + version_id + "/PCL/Setup.ini")
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	for line in text.split("\n", true):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("VersionServerAuthServer:"):
			return trimmed.substr("VersionServerAuthServer:".length()).strip_edges()
	return ""


static func thirdparty_token_path() -> String:
	return ConfigManager.auth_dir() + "/" + THIRDPARTY_TOKEN_NAME


static func token_example() -> String:
	return '{\n  "accessToken": "本地令牌",\n  "uuid": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",\n  "name": "玩家名"\n}'


static func _fail(code: String, ctx: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"username": "",
		"uuid": "",
		"access_token": "",
		"user_type": "",
		"token_path": "",
		"error": ErrorInfoScript.make(code, ctx),
	}


## 日志/UI 中展示命令时隐藏访问令牌。
static func redacted_argv(argv: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	var hide_next := false
	for arg in argv:
		if hide_next:
			out.append("***")
			hide_next = false
			continue
		if arg == "--accessToken":
			out.append(arg)
			hide_next = true
			continue
		if arg.begins_with("--accessToken="):
			out.append("--accessToken=***")
			continue
		out.append(arg)
	return out


static func command_preview(executable: String, argv: PackedStringArray) -> String:
	var parts := PackedStringArray([quote(executable)])
	for arg in redacted_argv(argv):
		parts.append(quote(arg))
	return " ".join(parts)


static func quote(value: String) -> String:
	if value.is_empty():
		return "\"\""
	if value.contains(" ") or value.contains("\t") or value.contains("\""):
		return "\"" + value.replace("\"", "\\\"") + "\""
	return value
