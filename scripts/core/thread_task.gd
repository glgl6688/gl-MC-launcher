class_name ThreadTask
extends Node
## 通用后台任务：在工作线程中执行一个 Callable，完成后用信号把结果交回主线程。
## 使用方式：
##   var task := ThreadTask.new()
##   add_child(task)
##   task.finished.connect(_on_done)
##   task.start(func(): return _heavy_work())
## 结果必须是可安全跨线程传递的值（Dictionary/Array/String/数字/布尔）。
## 注意：工作线程中禁止直接访问场景树、UI 或 autoload 的节点方法，
## 需要进度时使用 call_deferred。

signal finished(result: Variant)

var _thread: Thread = null
var _work: Callable = Callable()
var _finished_emitted := false


func start(work: Callable) -> bool:
	if _thread != null:
		push_warning("ThreadTask 已经启动，忽略重复调用")
		return false
	if not work.is_valid():
		call_deferred("_emit_result", {
			"ok": false,
			"error": {
				"code": "THREAD_TASK_INVALID",
				"title": "后台任务错误",
				"message": "后台任务没有可执行的内容。",
				"path": "",
				"fix_hint": "请重试；如果问题持续出现，请查看日志并向项目反馈。",
			},
		})
		return false
	_work = work
	_thread = Thread.new()
	var err := _thread.start(_thread_main)
	if err != OK:
		_thread = null
		call_deferred("_emit_result", {
			"ok": false,
			"error": {
				"code": "THREAD_START_FAILED",
				"title": "无法启动后台任务",
				"message": "创建后台线程失败（错误码 %d）。" % err,
				"path": "",
				"fix_hint": "请关闭其他占用资源的程序后重试；必要时重启启动器。",
			},
		})
		return false
	return true


func _thread_main() -> void:
	var result: Variant = null
	if _work.is_valid():
		result = _work.call()
	if result == null:
		result = {"ok": false}
	call_deferred("_emit_result", result)


func _emit_result(result: Variant) -> void:
	if _finished_emitted:
		return
	_finished_emitted = true
	if _thread != null:
		if _thread.is_started():
			_thread.wait_to_finish()
		_thread = null
	finished.emit(result)
	queue_free()


func _exit_tree() -> void:
	# 场景退出时等待线程结束，避免 Thread 对象未 join 被释放。
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null
