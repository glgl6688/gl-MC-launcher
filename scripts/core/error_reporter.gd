extends Node
## 统一错误上报：把 ErrorInfo 生成的错误写入日志并通知 UI。
## UI 只需连接 error_raised 信号即可弹出可复制路径的错误对话框。

signal error_raised(error: Dictionary)

const ErrorInfoScript = preload("res://scripts/core/error_info.gd")


func make(code: String, ctx: Dictionary = {}) -> Dictionary:
	return ErrorInfoScript.make(code, ctx)


func report(code: String, ctx: Dictionary = {}) -> Dictionary:
	var err := make(code, ctx)
	var path := str(err.get("path", ""))
	LogManager.error("[%s] %s%s" % [
		err.get("code", code),
		err.get("message", ""),
		"" if path.is_empty() else "\n路径：" + path,
	])
	if not str(err.get("fix_hint", "")).is_empty():
		LogManager.info("[修复建议] " + str(err.get("fix_hint", "")))
	error_raised.emit(err)
	return err


func report_error(error: Dictionary) -> void:
	var code := str(error.get("code", "UNKNOWN"))
	var path := str(error.get("path", ""))
	LogManager.error("[%s] %s%s" % [
		code,
		error.get("message", ""),
		"" if path.is_empty() else "\n路径：" + path,
	])
	error_raised.emit(error)
