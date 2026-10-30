class_name ResourceInstaller
extends Node
## 本地资源安装：Mod(.jar) / 光影(.zip) / 材质(.zip)
## 复制在后台线程执行，逐文件反馈进度；同名文件先备份为 .bak。

signal progress(percent: int, message: String)
signal finished(result: Dictionary)

const FileUtilsScript = preload("res://scripts/core/file_utils.gd")
const ErrorInfoScript = preload("res://scripts/core/error_info.gd")
const ThreadTaskScript = preload("res://scripts/core/thread_task.gd")

const KINDS := {
	"mod": {"dir": "mods", "ext": "jar", "label": "Mod"},
	"shader": {"dir": "shaderpacks", "ext": "zip", "label": "光影包"},
	"resource": {"dir": "resourcepacks", "ext": "zip", "label": "材质包"},
}

var _busy := false


func install_async(paths: PackedStringArray, kind: String, game_dir: String) -> bool:
	if _busy:
		LogManager.warn("已有资源安装任务正在进行")
		return false
	if not KINDS.has(kind):
		LogManager.error("未知的资源类型：" + kind)
		return false
	_busy = true
	progress.emit(0, "准备复制…")
	var task = ThreadTaskScript.new()
	add_child(task)
	task.finished.connect(_on_task_finished)
	task.start(func() -> Dictionary:
		return install_sync(paths, kind, game_dir, _on_progress)
	)
	return true


func _on_progress(percent: int, message: String) -> void:
	progress.emit(percent, message)


func _on_task_finished(result: Variant) -> void:
	_busy = false
	if not (result is Dictionary):
		result = {
			"ok": false,
			"copied": [],
			"backups": [],
			"errors": ["后台任务没有返回有效结果"],
		}
	finished.emit(result)


static func install_sync(paths: PackedStringArray, kind: String, game_dir: String, progress_cb: Callable = Callable()) -> Dictionary:
	var info: Dictionary = KINDS.get(kind, {})
	var target_dir := FileUtilsScript.join(game_dir, str(info.get("dir", "mods")))
	var mk := FileUtilsScript.ensure_dir(target_dir)
	if mk != OK:
		return {
			"ok": false,
			"copied": [],
			"backups": [],
			"errors": ["无法创建目标目录：" + target_dir + "（" + error_string(mk) + "）"],
			"target_dir": target_dir,
		}
	var total := 0
	for path in paths:
		var size := FileUtilsScript.file_size(path)
		if size > 0:
			total += size
	var done_bytes := 0
	var copied: Array[String] = []
	var unchanged: Array[String] = []
	var backups: Array[String] = []
	var errors: Array[String] = []
	for i in range(paths.size()):
		var source := FileUtilsScript.normalize(paths[i])
		var file_name := source.get_file()
		var message := "正在复制 %s（%d/%d）" % [file_name, i + 1, paths.size()]
		_emit_progress(progress_cb, int(round(100.0 * done_bytes / maxf(1.0, total))), message)
		if not FileAccess.file_exists(source):
			errors.append("源文件不存在：" + source)
			continue
		var ext := source.get_extension().to_lower()
		if ext != str(info.get("ext", "")):
			errors.append("“%s”扩展名为 .%s，%s需要 .%s 文件。" % [file_name, ext, info.get("label", "该类型"), info.get("ext", "")])
			continue
		var target := FileUtilsScript.join(target_dir, file_name)
		if FileUtilsScript.normalize(source) == FileUtilsScript.normalize(target):
			unchanged.append(target)
			var existing_size := maxi(0, FileUtilsScript.file_size(source))
			done_bytes += existing_size
			_emit_progress(progress_cb, int(round(100.0 * done_bytes / maxf(1.0, total))), "已存在，跳过：" + file_name)
			continue
		var backup := FileUtilsScript.backup_file(target)
		if not bool(backup.get("ok", false)):
			errors.append("无法备份已有文件：%s（%s）" % [target, backup.get("error", "")])
			continue
		if not str(backup.get("backup_path", "")).is_empty():
			backups.append(str(backup.get("backup_path", "")))
		var size := FileUtilsScript.file_size(source)
		var base_done := done_bytes
		var total_all := total
		var file_progress := func(copied_bytes: int, file_total: int) -> void:
			var overall := int(round(100.0 * (base_done + copied_bytes) / maxf(1.0, total_all)))
			var file_pct := int(round(100.0 * copied_bytes / maxf(1.0, file_total)))
			_emit_progress(progress_cb, overall, "正在复制 %s（%d%%）" % [file_name, file_pct])
		var result := FileUtilsScript.copy_file_chunked(source, target, file_progress)
		if bool(result.get("ok", false)):
			copied.append(target)
			done_bytes += maxi(0, size)
			_emit_progress(progress_cb, int(round(100.0 * done_bytes / maxf(1.0, total))), "已复制 " + file_name)
		else:
			errors.append("复制失败：%s -> %s（%s）" % [source, target, result.get("error", "")])
	_emit_progress(progress_cb, 100, "完成")
	return {
		"ok": errors.is_empty(),
		"copied": copied,
		"unchanged": unchanged,
		"backups": backups,
		"errors": errors,
		"target_dir": target_dir,
	}


static func _emit_progress(cb: Callable, percent: int, message: String) -> void:
	if cb.is_valid():
		cb.call_deferred(clampi(percent, 0, 100), message)


static func extension_for(kind: String) -> String:
	var info: Dictionary = KINDS.get(kind, {})
	return str(info.get("ext", ""))


static func label_for(kind: String) -> String:
	var info: Dictionary = KINDS.get(kind, {})
	return str(info.get("label", "资源"))
