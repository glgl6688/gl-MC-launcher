class_name ProcessRunner
extends Node
## 启动 Java 进程，并把 stdout/stderr 实时写入实例 logs/latest.log。
## 使用 Godot 4.3+ 的 OS.execute_with_pipe（非阻塞）：不阻塞主线程，也不拼接 shell 字符串。
## 注意：启动器退出后管道会关闭，正在运行的游戏可能失去后续输出；
## 建议在游戏运行期间保持启动器打开（UI 会显示进程状态）。

signal process_finished(result: Dictionary)

const FileUtilsScript = preload("res://scripts/core/file_utils.gd")
const ErrorInfoScript = preload("res://scripts/core/error_info.gd")

var _pid := -1
var _out_pipe: FileAccess = null
var _err_pipe: FileAccess = null
var _reader: Thread = null
var _log_path := ""
var _running := false
var _stop_requested := false
var _finalized := false
var _poll_accum := 0.0
var _start_ticks := 0


func start(java_path: String, argv: PackedStringArray, log_path: String, command_preview: String) -> Dictionary:
	if _running:
		return {
			"ok": false,
			"error": ErrorInfoScript.make("LAUNCH_BUSY", {}),
		}
	var log_p := FileUtilsScript.normalize(log_path)
	var mk := FileUtilsScript.ensure_dir(log_p.get_base_dir())
	if mk != OK:
		return {
			"ok": false,
			"error": ErrorInfoScript.make("LAUNCH_FAILED", {
				"path": java_path,
				"reason": "无法创建日志目录：" + error_string(mk),
			}),
		}
	_rotate_old_log(log_p)
	var header := "=== gl启动器启动记录 ===\n时间：%s\nJava：%s\n命令：%s\n\n" % [
		Time.get_datetime_string_from_system(true),
		java_path,
		command_preview,
	]
	var written := FileUtilsScript.write_text(log_p, header)
	if not bool(written.get("ok", false)):
		return {
			"ok": false,
			"error": ErrorInfoScript.make("LAUNCH_FAILED", {
				"path": java_path,
				"reason": "无法写入游戏日志：" + str(written.get("error", "")),
			}),
		}
	var pipe := OS.execute_with_pipe(java_path, argv, false)
	# TODO: 验证 Godot 4.3 签名。Godot 4.7 的 execute_with_pipe 只接受 3 个参数；
	# 旧版本可能多出 read_stderr / open_console。这里使用三参数兼容形式，
	# 并通过返回字典中可选的 "stderr" 管道做容错（旧版本没有该键时只读 stdout）。
	if pipe.is_empty():
		# 极端环境（或旧引擎）无法建立管道时，退化为普通进程启动：
		# 游戏仍可运行，但本次输出不会写入日志，会给出警告。
		var fallback_pid := OS.create_process(java_path, argv)
		if fallback_pid <= 0:
			return {
				"ok": false,
				"error": ErrorInfoScript.make("LAUNCH_FAILED", {
					"path": java_path,
					"reason": "无法创建进程（管道与普通启动都失败）",
				}),
			}
		_pid = fallback_pid
		_log_path = log_p
		_running = true
		_stop_requested = false
		_finalized = false
		_poll_accum = 0.0
		_start_ticks = Time.get_ticks_msec()
		set_process(true)
		var note := "当前环境无法创建输出管道，游戏已启动，但本次 stdout/stderr 不会写入日志。"
		LogManager.warn(note)
		var log_append := FileAccess.open(log_p, FileAccess.READ_WRITE)
		if log_append != null:
			log_append.seek_end()
			log_append.store_string("\n[启动器] " + note + "\n")
			log_append.close()
		return {"ok": true, "pid": fallback_pid, "log_path": log_p, "warning": note, "error": {}}
	var pid := int(pipe.get("pid", -1))
	if pid <= 0:
		return {
			"ok": false,
			"error": ErrorInfoScript.make("LAUNCH_FAILED", {
				"path": java_path,
				"reason": "进程 PID 无效",
			}),
		}
	_pid = pid
	_out_pipe = pipe.get("stdio", null)
	_err_pipe = pipe.get("stderr", null)
	_log_path = log_p
	_running = true
	_stop_requested = false
	_finalized = false
	_poll_accum = 0.0
	_start_ticks = Time.get_ticks_msec()
	_reader = Thread.new()
	var err := _reader.start(_reader_main)
	if err != OK:
		_running = false
		_reader = null
		_close_pipes()
		return {
			"ok": false,
			"error": ErrorInfoScript.make("LAUNCH_FAILED", {
				"path": java_path,
				"reason": "无法创建输出读取线程：" + error_string(err),
			}),
		}
	set_process(true)
	LogManager.info("游戏进程已启动，PID=%d，日志：%s" % [pid, FileUtilsScript.to_global(log_p)])
	return {"ok": true, "pid": pid, "log_path": log_p, "error": {}}


func is_running() -> bool:
	return _running


func current_pid() -> int:
	return _pid


func _process(delta: float) -> void:
	if not _running:
		return
	_poll_accum += delta
	if _poll_accum < 0.4:
		return
	_poll_accum = 0.0
	if not OS.is_process_running(_pid):
		# 快速退出的进程给一点宽限，让读取线程把剩余输出写完。
		if Time.get_ticks_msec() - _start_ticks < 400:
			return
		_finalize()


func _finalize() -> void:
	if _finalized:
		return
	_finalized = true
	_running = false
	_stop_requested = true
	if _reader != null:
		if _reader.is_started():
			_reader.wait_to_finish()
		_reader = null
	_close_pipes()
	_append_footer()
	set_process(false)
	LogManager.info("游戏进程已结束，PID=%d" % _pid)
	process_finished.emit({"pid": _pid, "log_path": _log_path, "exit_code": -1})


func _reader_main() -> void:
	var log_file := FileAccess.open(_log_path, FileAccess.READ_WRITE)
	if log_file == null:
		_stop_requested = true
		return
	log_file.seek_end()
	while not _stop_requested:
		var produced := false
		for pipe in [_out_pipe, _err_pipe]:
			if pipe == null:
				continue
			while true:
				var chunk: PackedByteArray = pipe.get_buffer(32768)
				if chunk.is_empty():
					break
				produced = true
				log_file.store_buffer(chunk)
		if produced:
			log_file.flush()
		else:
			OS.delay_msec(50)
	# 进程结束后再排空一次管道，避免丢失最后几行。
	for pipe in [_out_pipe, _err_pipe]:
		if pipe == null:
			continue
		while true:
			var chunk2: PackedByteArray = pipe.get_buffer(65536)
			if chunk2.is_empty():
				break
			log_file.store_buffer(chunk2)
	log_file.flush()
	log_file.close()


func _close_pipes() -> void:
	if _out_pipe != null:
		_out_pipe.close()
		_out_pipe = null
	if _err_pipe != null:
		_err_pipe.close()
		_err_pipe = null


func _append_footer() -> void:
	if _log_path.is_empty():
		return
	var f := FileAccess.open(_log_path, FileAccess.READ_WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_string("\n=== 游戏进程结束 %s ===\n" % Time.get_datetime_string_from_system(true))
	f.close()


func _rotate_old_log(log_path: String) -> void:
	if not FileAccess.file_exists(log_path):
		return
	var stamp := Time.get_datetime_string_from_system(false, true)
	stamp = stamp.replace("-", "").replace(":", "").replace("T", "-")
	var rotated := "%s-%s.log" % [log_path.get_basename(), stamp]
	DirAccess.rename_absolute(log_path, rotated)
	_cleanup_old_logs(log_path.get_base_dir())


func _cleanup_old_logs(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	var prefix := "latest-"
	var archives: Array[String] = []
	for name in d.get_files():
		if name.begins_with(prefix) and name.ends_with(".log"):
			archives.append(name)
	archives.sort()
	while archives.size() > 5:
		var oldest: String = archives.pop_front()
		DirAccess.remove_absolute(FileUtilsScript.join(dir, oldest))


func _exit_tree() -> void:
	if _reader != null:
		_stop_requested = true
		if _reader.is_started():
			_reader.wait_to_finish()
		_reader = null
	_close_pipes()
