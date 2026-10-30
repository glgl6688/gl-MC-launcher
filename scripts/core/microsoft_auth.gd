class_name MicrosoftAuth
extends Node
## Microsoft 设备码登录：Microsoft → Xbox Live → XSTS → Minecraft Services → 角色。
## 使用 Microsoft 官方 Minecraft 启动器的 Live 设备码客户端，不需要用户填写 Azure client_id。

signal code_ready(user_code: String, verification_uri: String, expires_in: int)
signal finished(result: Dictionary)
signal status_changed(message: String)

const ErrorInfoScript = preload("res://scripts/core/error_info.gd")

## 官方 Minecraft 启动器的公共 Live 客户端 ID。
const CLIENT_ID := "00000000402b5328"
const DEVICE_URL := "https://login.live.com/oauth20_connect.srf"
const TOKEN_URL := "https://login.live.com/oauth20_token.srf"
const XBL_URL := "https://user.auth.xboxlive.com/user/authenticate"
const XSTS_URL := "https://xsts.auth.xboxlive.com/xsts/authorize"
const MC_LOGIN_URL := "https://api.minecraftservices.com/authentication/login_with_xbox"
const MC_PROFILE_URL := "https://api.minecraftservices.com/minecraft/profile"

var _http: HTTPRequest
var _timer: Timer
var _state := "idle"
var _client_id := ""
var _device_code := ""
var _interval := 5
var _expires_at := 0
var _ms_access_token := ""
var _refresh_token := ""
var _xbl_token := ""
var _uhs := ""
var _mc_token := ""

# 默认使用官方端点；测试可改成 mock 服务器。
var device_url := DEVICE_URL
var token_url := TOKEN_URL
var xbl_url := XBL_URL
var xsts_url := XSTS_URL
var mc_login_url := MC_LOGIN_URL
var mc_profile_url := MC_PROFILE_URL


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 30.0
	_http.accept_gzip = true
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_poll_token)
	add_child(_timer)


func is_busy() -> bool:
	return _state != "idle"


func start(client_id: String = "") -> Dictionary:
	if _state != "idle":
		return {"ok": false, "error": ErrorInfoScript.make("MS_LOGIN_FAILED", {"reason": "已有登录请求正在进行"})}
	_client_id = CLIENT_ID if client_id.strip_edges().is_empty() else client_id.strip_edges()
	_state = "device"
	status_changed.emit("正在向 Microsoft 申请设备码…")
	var body := "client_id=%s&scope=offline_access%%20XboxLive.signin&response_type=device_code" % _client_id.uri_encode()
	var err := _http.request(device_url, _form_headers(), HTTPClient.METHOD_POST, body)
	if err != OK:
		_state = "idle"
		return {"ok": false, "error": ErrorInfoScript.make("MS_NETWORK_ERROR", {"path": device_url, "reason": error_string(err)})}
	return {"ok": true, "pending": true}


func cancel() -> void:
	_state = "idle"
	if _timer != null:
		_timer.stop()


func _form_headers() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/x-www-form-urlencoded",
		"Accept: application/json",
		"User-Agent: gl-launcher/1.0.0",
	])


func _json_headers() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
		"User-Agent: gl-launcher/1.0.0",
	])


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _state == "idle":
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail("MS_NETWORK_ERROR", {"reason": "网络请求失败（结果码 %d）" % result})
		return
	var text := body.get_string_from_utf8()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		_fail("MS_BAD_RESPONSE", {"reason": "JSON 解析失败：第 %d 行 %s" % [parser.get_error_line(), parser.get_error_message()]})
		return
	if not (parser.data is Dictionary):
		_fail("MS_BAD_RESPONSE", {"reason": "JSON 根节点不是对象"})
		return
	var data: Dictionary = parser.data
	match _state:
		"device":
			_handle_device(data, response_code)
		"poll":
			_handle_poll(data, response_code)
		"xbl":
			_handle_xbl(data, response_code)
		"xsts":
			_handle_xsts(data, response_code)
		"mc":
			_handle_mc(data, response_code)
		"profile":
			_handle_profile(data, response_code)
		_:
			_fail("MS_LOGIN_FAILED", {"reason": "未知的登录阶段"})


func _handle_device(data: Dictionary, code: int) -> void:
	if code != 200:
		_fail("MS_LOGIN_FAILED", {"reason": _server_error(data, code)})
		return
	_device_code = str(data.get("device_code", ""))
	var user_code := str(data.get("user_code", ""))
	var uri := str(data.get("verification_uri", "https://microsoft.com/link"))
	var expires := int(data.get("expires_in", 900))
	_interval = maxi(1, int(data.get("interval", 5)))
	if _device_code.is_empty() or user_code.is_empty():
		_fail("MS_BAD_RESPONSE", {"reason": "设备码响应缺少 device_code 或 user_code"})
		return
	_expires_at = Time.get_ticks_msec() + expires * 1000
	_state = "poll"
	code_ready.emit(user_code, uri, expires)
	status_changed.emit("请在浏览器输入验证码并完成 Microsoft 登录…")
	_timer.start(float(_interval))


func _poll_token() -> void:
	if _state != "poll":
		return
	if Time.get_ticks_msec() > _expires_at:
		_fail("MS_LOGIN_FAILED", {"reason": "设备码已过期，请重新登录"})
		return
	_state = "poll"
	var body := "grant_type=urn%%3Aietf%%3Aparams%%3Aoauth%%3Agrant-type%%3Adevice_code&client_id=%s&device_code=%s" % [
		_client_id.uri_encode(), _device_code.uri_encode(),
	]
	var err := _http.request(token_url, _form_headers(), HTTPClient.METHOD_POST, body)
	if err != OK:
		_fail("MS_NETWORK_ERROR", {"path": token_url, "reason": error_string(err)})


func _handle_poll(data: Dictionary, code: int) -> void:
	if code == 200:
		_ms_access_token = str(data.get("access_token", ""))
		_refresh_token = str(data.get("refresh_token", ""))
		if _ms_access_token.is_empty():
			_fail("MS_BAD_RESPONSE", {"reason": "Microsoft 未返回 access_token"})
			return
		_state = "xbl"
		status_changed.emit("Microsoft 登录成功，正在验证 Xbox Live…")
		_post_json(xbl_url, {
			"Properties": {
				"AuthMethod": "RPS",
				"SiteName": "user.auth.xboxlive.com",
				"RpsTicket": "d=" + _ms_access_token,
			},
			"RelyingParty": "http://auth.xboxlive.com",
			"TokenType": "JWT",
		})
		return
	var error := str(data.get("error", ""))
	if error == "authorization_pending":
		_timer.start(float(_interval))
		return
	if error == "slow_down":
		_interval += 5
		_timer.start(float(_interval))
		return
	if error == "expired_token":
		_fail("MS_LOGIN_FAILED", {"reason": "验证码已过期，请重新登录"})
		return
	if error == "authorization_declined":
		_fail("MS_LOGIN_FAILED", {"reason": "你取消了 Microsoft 登录授权"})
		return
	_fail("MS_LOGIN_FAILED", {"reason": _server_error(data, code)})


func _handle_xbl(data: Dictionary, code: int) -> void:
	if code != 200:
		_fail("MS_LOGIN_FAILED", {"reason": "Xbox Live 认证失败：" + _server_error(data, code)})
		return
	_xbl_token = str(data.get("Token", ""))
	if _xbl_token.is_empty():
		_fail("MS_BAD_RESPONSE", {"reason": "Xbox Live 未返回 Token"})
		return
	_state = "xsts"
	status_changed.emit("正在获取 Xbox 安全令牌…")
	_post_json(xsts_url, {
		"Properties": {
			"SandboxId": "RETAIL",
			"UserTokens": [_xbl_token],
		},
		"RelyingParty": "rp://api.minecraftservices.com/",
		"TokenType": "JWT",
	})


func _handle_xsts(data: Dictionary, code: int) -> void:
	if code != 200:
		var xerr := int(data.get("XErr", 0))
		var reason := _xsts_message(xerr)
		_fail("MS_LOGIN_FAILED", {"reason": reason})
		return
	_xbl_token = str(data.get("Token", ""))
	var claims: Variant = data.get("DisplayClaims", {})
	_uhs = ""
	if claims is Dictionary:
		var xui: Variant = claims.get("xui", [])
		if xui is Array and not xui.is_empty() and xui[0] is Dictionary:
			_uhs = str(xui[0].get("uhs", ""))
	if _xbl_token.is_empty() or _uhs.is_empty():
		_fail("MS_BAD_RESPONSE", {"reason": "XSTS 响应缺少 Token 或 uhs"})
		return
	_state = "mc"
	status_changed.emit("正在登录 Minecraft Services…")
	_post_json(mc_login_url, {
		"identityToken": "XBL3.0 x=" + _uhs + ";" + _xbl_token,
	})


func _handle_mc(data: Dictionary, code: int) -> void:
	if code != 200:
		_fail("MS_LOGIN_FAILED", {"reason": "Minecraft 登录失败：" + _server_error(data, code)})
		return
	var token := str(data.get("access_token", ""))
	if token.is_empty():
		_fail("MS_BAD_RESPONSE", {"reason": "Minecraft 未返回 access_token"})
		return
	_mc_token = token
	_state = "profile"
	status_changed.emit("正在读取 Minecraft 角色…")
	var headers := PackedStringArray([
		"Authorization: Bearer " + token,
		"Accept: application/json",
		"User-Agent: gl-launcher/1.0.0",
	])
	var err := _http.request(mc_profile_url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		_fail("MS_NETWORK_ERROR", {"path": mc_profile_url, "reason": error_string(err)})


func _handle_profile(data: Dictionary, code: int) -> void:
	if code != 200:
		if code == 404:
			_fail("MS_NO_MINECRAFT", {})
			return
		_fail("MS_LOGIN_FAILED", {"reason": "读取角色失败：" + _server_error(data, code)})
		return
	var uuid := str(data.get("id", ""))
	var name := str(data.get("name", ""))
	if uuid.is_empty() or name.is_empty():
		_fail("MS_BAD_RESPONSE", {"reason": "角色信息缺少 id 或 name"})
		return
	_state = "idle"
	_timer.stop()
	finished.emit({
		"ok": true,
		"access_token": _mc_token,
		"refresh_token": _refresh_token,
		"uuid": uuid,
		"name": name,
		"client_id": _client_id,
		"error": {},
	})


func _post_json(url: String, payload: Dictionary) -> void:
	var err := _http.request(url, _json_headers(), HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		_fail("MS_NETWORK_ERROR", {"path": url, "reason": error_string(err)})


func _server_error(data: Dictionary, code: int) -> String:
	var msg := str(data.get("error_description", data.get("errorMessage", data.get("error", ""))))
	if msg.is_empty():
		msg = "HTTP %d" % code
	return msg


func _xsts_message(xerr: int) -> String:
	match xerr:
		2148916233:
			return "该 Microsoft 账号还没有 Xbox 账号，请先在 xbox.com 创建。"
		2148916235:
			return "该 Xbox 账号所在地区不可用。"
		2148916236, 2148916237:
			return "该账号需要在 Xbox 页面完成成人验证。"
		2148916238:
			return "该账号是儿童账号，需要加入 Microsoft 家庭。"
		_:
			return "Xbox 安全令牌获取失败（XErr=%d）" % xerr


func _fail(code: String, ctx: Dictionary) -> void:
	_state = "idle"
	if _timer != null:
		_timer.stop()
	finished.emit({"ok": false, "error": ErrorInfoScript.make(code, ctx)})
