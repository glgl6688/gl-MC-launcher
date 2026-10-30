extends Node
## 进程运行器集成测试：用系统命令模拟游戏进程，验证非阻塞输出捕获、日志写入与结束检测。

const ProcessRunnerScript = preload("res://scripts/core/process_runner.gd")
const FileUtilsScript = preload("res://scripts/core/file_utils.gd")

var _runner
var _done := false
var _log_path := ""
var _failures: Array[String] = []


func _ready() -> void:
	var base := FileUtilsScript.normalize(OS.get_environment("TEMP")) + "/gl_process_%d" % Time.get_ticks_usec()
	_log_path = base + "/logs/latest.log"
	FileUtilsScript.write_text(_log_path, "OLD-LOG-CONTENT\n")
	_runner = ProcessRunnerScript.new()
	add_child(_runner)
	_runner.process_finished.connect(_on_finished)
	var exe := "C:/Windows/System32/cmd.exe"
	var args := PackedStringArray(["/c", "echo hello-out & echo hello-err 1>&2 & ping -n 2 127.0.0.1 >nul & echo bye"])
	if OS.get_name() != "Windows":
		exe = "/bin/sh"
		args = PackedStringArray(["-c", "echo hello-out; echo hello-err 1>&2; sleep 1; echo bye"])
	var res: Dictionary = _runner.start(exe, args, _log_path, "test shell echo")
	_check("进程启动成功", bool(res.get("ok", false)), str(res.get("error", {})))
	_check("进程 PID 有效", int(res.get("pid", -1)) > 0)
	get_tree().create_timer(15.0).timeout.connect(func() -> void:
		if not _done:
			print("FAIL  进程测试超时")
			get_tree().quit(1)
	)


func _on_finished(result: Dictionary) -> void:
	_done = true
	var text := ""
	var f := FileAccess.open(_log_path, FileAccess.READ)
	if f != null:
		text = f.get_as_text()
		f.close()
	_check("日志包含 stdout", text.contains("hello-out"), text)
	_check("日志包含 stderr", text.contains("hello-err"), text)
	_check("日志包含结束标记", text.contains("bye") and text.contains("游戏进程结束"), text)
	_check("日志包含启动头", text.contains("gl启动器启动记录"), text)
	_check("旧日志已轮转", _has_rotated_log(_log_path.get_base_dir()), text)
	print("")
	if _failures.is_empty():
		print("进程测试全部通过")
		get_tree().quit(0)
	else:
		print("进程测试失败 %d 项：" % _failures.size())
		for item in _failures:
			print("  - ", item)
		get_tree().quit(1)


func _has_rotated_log(dir: String) -> bool:
	var d := DirAccess.open(dir)
	if d == null:
		return false
	for name in d.get_files():
		if str(name).begins_with("latest-") and str(name).ends_with(".log"):
			return true
	return false


func _check(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("PASS  ", name)
	else:
		_failures.append(name + ("" if detail.is_empty() else " :: " + detail.substr(0, 400)))
		print("FAIL  ", name)
