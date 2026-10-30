class_name OnlineAuth
extends Node
## 第三方 Yggdrasil 登录。只在用户点击「登录第三方」时联网。
## 密码只存在于本次请求的内存中，不写入磁盘、不写日志；成功后由 main 保存返回的令牌。

signal finished(result: Dictionary)
signal status_changed(message: String)

const ErrorInfoScript = preload("res://scripts/core/error_info.gd")
const AuthHelperScript = preload("res://scripts/core/auth_helper.gd")

var _http: HTTPRequest
var _busy := false
var _server := ""


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 30.0
	_http.accept_gzip = true
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func is_busy() -> bool:
	return _busy


## 返回 {ok: true, pending: true} 或 {ok: false, error: Dictionary}
func login(auth_url: String, username: String, password: String) -> Dictionary:
	if _busy:
		return {"ok": false, "error": ErrorInfoScript.make("AUTH_LOGIN_FAILED", {"reason": "已有登录请求正在进行"})}
	var base := _normalize_server(auth_url)
	if base.is_empty():
		return {"ok": false, "error": ErrorInfoScript.make("AUTH_SERVER_REQUIRED", {"path": auth_url})}
	if base.begins_with("http://") and not (base.begins_with("http://127.0.0.1") or base.begins_with("http://localhost")):
		return {"ok": false, "error": ErrorInfoScript.make("AUTH_INSECURE_SERVER", {"path": base})}
	if username.strip_edges().is_empty() or password.is_empty():
		return {"ok": false, "error": ErrorInfoScript.make("AUTH_PASSWORD_REQUIRED", {})}
	var body := {
		"agent": {"name": "Minecraft", "version": 1},
		"username": username.strip_edges(),
		"password": password,
		"clientToken": Crypto.new().generate_random_bytes(16).hex_encode(),
		"requestUser": true,
	}
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
		"User-Agent: gl-launcher/1.0.0",
	])
	var url := base + "/authserver/authenticate"
	status_changed.emit("正在连接认证服务器…")
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		return {
			"ok": false,
			"error": ErrorInfoScript.make("AUTH_NETWORK_ERROR", {
				"path": url,
				"reason": error_string(err),
			}),
		}
	_busy = true
	_server = base
	return {"ok": true, "pending": true}


func _normalize_server(auth_url: String) -> String:
	var base := auth_url.strip_edges().trim_suffix("/")
	if base.is_empty() or not (base.begins_with("https://") or base.begins_with("http://")):
		return ""
	if base.ends_with("/authserver/authenticate"):
		base = base.trim_suffix("/authenticate").trim_suffix("/authserver")
	elif base.ends_with("/authserver"):
		base = base.trim_suffix("/authserver")
	return base


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	if result != HTTPRequest.RESULT_SUCCESS:
		finished.emit({
			"ok": false,
			"error": ErrorInfoScript.make("AUTH_NETWORK_ERROR", {
				"path": _server + "/authserver/authenticate",
				"reason": "网络请求失败（结果码 %d）" % result,
			}),
		})
		return
	var text := body.get_string_from_utf8()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		finished.emit({
			"ok": false,
			"error": ErrorInfoScript.make("AUTH_BAD_RESPONSE", {
				"reason": "第 %d 行：%s" % [parser.get_error_line(), parser.get_error_message()],
			}),
		})
		return
	if not (parser.data is Dictionary):
		finished.emit({"ok": false, "error": ErrorInfoScript.make("AUTH_BAD_RESPONSE", {"reason": "JSON 根节点不是对象"})})
		return
	var data: Dictionary = parser.data
	if response_code != 200:
		var reason := str(data.get("errorMessage", data.get("error", "HTTP %d" % response_code)))
		finished.emit({"ok": false, "error": ErrorInfoScript.make("AUTH_LOGIN_FAILED", {"reason": reason})})
		return
	var token := str(data.get("accessToken", ""))
	var client_token := str(data.get("clientToken", ""))
	var profile: Variant = data.get("selectedProfile", {})
	if token.is_empty() or not (profile is Dictionary) or profile.is_empty():
		finished.emit({
			"ok": false,
			"error": ErrorInfoScript.make("AUTH_LOGIN_FAILED", {"reason": "服务器未返回 accessToken 或 selectedProfile"}),
		})
		return
	var profile_dict: Dictionary = profile
	var uuid := str(profile_dict.get("id", ""))
	var name := str(profile_dict.get("name", ""))
	if uuid.is_empty() or name.is_empty():
		finished.emit({"ok": false, "error": ErrorInfoScript.make("AUTH_BAD_RESPONSE", {"reason": "角色信息缺少 id 或 name"})})
		return
	finished.emit({
		"ok": true,
		"access_token": token,
		"client_token": client_token,
		"uuid": uuid,
		"name": name,
		"server": _server,
		"error": {},
	})
