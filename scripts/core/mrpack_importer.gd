class_name MrpackImporter
extends Node
## .mrpack（Modrinth 整合包）本地导入。
## 只处理压缩包自带的 overrides / client-overrides，以及用户指定“本地来源目录”中已存在、
## 哈希可验证的 files 条目；不会联网下载任何文件。缺失项会在结果中列出。

signal progress(percent: int, message: String)
signal finished(result: Dictionary)

const FileUtilsScript = preload("res://scripts/core/file_utils.gd")
const ErrorInfoScript = preload("res://scripts/core/error_info.gd")
const ThreadTaskScript = preload("res://scripts/core/thread_task.gd")

const INDEX_FILE := "modrinth.index.json"
const MAX_OVERRIDE_BYTES := 268435456

var _busy := false


func import_async(mrpack_path: String, target_game_dir: String, source_dir: String = "") -> bool:
	if _busy:
		LogManager.warn("已有整合包导入任务正在进行")
		return false
	_busy = true
	progress.emit(0, "正在读取整合包…")
	var task = ThreadTaskScript.new()
	add_child(task)
	task.finished.connect(_on_task_finished)
	task.start(func() -> Dictionary:
		return import_sync(mrpack_path, target_game_dir, source_dir, _on_progress)
	)
	return true


func _on_progress(percent: int, message: String) -> void:
	progress.emit(percent, message)


func _on_task_finished(result: Variant) -> void:
	_busy = false
	if not (result is Dictionary):
		result = {"ok": false, "error": ErrorInfoScript.make("MRPACK_IMPORT_FAILED", {"reason": "后台任务没有返回有效结果"})}
	finished.emit(result)


static func import_sync(mrpack_path: String, target_game_dir: String, source_dir: String = "", progress_cb: Callable = Callable()) -> Dictionary:
	var pack := FileUtilsScript.normalize(mrpack_path)
	var game_dir := FileUtilsScript.normalize(target_game_dir)
	var source := FileUtilsScript.normalize(source_dir)
	if not FileAccess.file_exists(pack):
		return _fatal("MRPACK_INVALID_ZIP", {"path": pack, "reason": "文件不存在"})
	if game_dir.is_empty():
		return _fatal("MRPACK_IMPORT_FAILED", {"reason": "目标游戏目录为空"})
	var zip := ZIPReader.new()
	# TODO: 验证 Godot 4.3 的 ZIPReader/ZIPPacker 签名；当前在 4.7.2 上验证通过。
	var open_err := zip.open(pack)
	if open_err != OK:
		return _fatal("MRPACK_INVALID_ZIP", {"path": pack, "reason": error_string(open_err)})
	var zip_files := zip.get_files()
	if not zip_files.has(INDEX_FILE):
		zip.close()
		return _fatal("MRPACK_INDEX_MISSING", {"path": pack})
	var index_bytes := zip.read_file(INDEX_FILE)
	if index_bytes.is_empty():
		zip.close()
		return _fatal("MRPACK_INDEX_INVALID", {"path": pack, "reason": "索引文件为空或读取失败"})
	var parser := JSON.new()
	if parser.parse(index_bytes.get_string_from_utf8()) != OK:
		var line := parser.get_error_line()
		var msg := parser.get_error_message()
		zip.close()
		return _fatal("MRPACK_INDEX_INVALID", {"path": pack, "reason": "第 %d 行：%s" % [line, msg]})
	if not (parser.data is Dictionary):
		zip.close()
		return _fatal("MRPACK_INDEX_INVALID", {"path": pack, "reason": "JSON 根节点不是对象"})
	var index: Dictionary = parser.data
	var mk := FileUtilsScript.ensure_dirs(PackedStringArray([
		game_dir,
		FileUtilsScript.join(game_dir, "mods"),
		FileUtilsScript.join(game_dir, "config"),
	]))
	if mk != OK:
		zip.close()
		return _fatal("MRPACK_IMPORT_FAILED", {"reason": "无法创建目标游戏目录：" + error_string(mk)})

	var overrides: Array[String] = []
	for entry in zip_files:
		var name := str(entry)
		if name.ends_with("/"):
			continue
		if name.begins_with("overrides/") or name.begins_with("client-overrides/"):
			overrides.append(name)
	var files: Array = index.get("files", []) if index.get("files", []) is Array else []
	var total_steps := overrides.size() + files.size()
	var step := 0
	var copied: Array[String] = []
	var unchanged: Array[String] = []
	var backups: Array[String] = []
	var missing: Array[Dictionary] = []
	var errors: Array[String] = []
	var warnings: Array[String] = []

	for entry in overrides:
		step += 1
		var rel := str(entry).trim_prefix("overrides/").trim_prefix("client-overrides/")
		_emit_progress(progress_cb, _percent(step - 1, total_steps), "正在导入整合包文件：" + rel)
		if not FileUtilsScript.is_safe_relative(rel):
			warnings.append("已跳过不安全的路径：" + str(entry))
			continue
		var bytes := zip.read_file(entry)
		if bytes.size() > MAX_OVERRIDE_BYTES:
			warnings.append("文件过大，已跳过：" + rel)
			continue
		var dst := FileUtilsScript.join(game_dir, rel)
		var backup := FileUtilsScript.backup_file(dst)
		if not bool(backup.get("ok", false)):
			errors.append("无法备份：" + dst + "（" + str(backup.get("error", "")) + "）")
			continue
		if not str(backup.get("backup_path", "")).is_empty():
			backups.append(str(backup.get("backup_path", "")))
		var written := FileUtilsScript.write_bytes(dst, bytes)
		if bool(written.get("ok", false)):
			copied.append(dst)
		else:
			errors.append("写入失败：" + dst + "（" + str(written.get("error", "")) + "）")

	for file_entry in files:
		step += 1
		if not (file_entry is Dictionary):
			continue
		var info: Dictionary = file_entry
		var rel_path := str(info.get("path", ""))
		_emit_progress(progress_cb, _percent(step - 1, total_steps), "正在处理：" + rel_path)
		if not FileUtilsScript.is_safe_relative(rel_path):
			warnings.append("已跳过不安全的条目路径：" + rel_path)
			continue
		var env: Variant = info.get("env", {})
		if env is Dictionary and str(env.get("client", "")) == "unsupported":
			continue
		var target_file := FileUtilsScript.join(game_dir, rel_path)
		var local := ""
		if not source.is_empty():
			var candidate := FileUtilsScript.join(source, rel_path)
			if FileAccess.file_exists(candidate):
				local = candidate
		if local.is_empty() and FileAccess.file_exists(target_file):
			local = target_file
		if local.is_empty():
			missing.append({
				"path": rel_path,
				"downloads": info.get("downloads", []),
				"reason": "本地未找到同名文件",
			})
			continue
		var hash_check := _verify_hashes(local, info.get("hashes", {}), int(info.get("fileSize", -1)))
		if not str(hash_check.get("note", "")).is_empty() and not warnings.has(str(hash_check["note"])):
			warnings.append(str(hash_check["note"]))
		if not bool(hash_check.get("ok", true)):
			missing.append({
				"path": rel_path,
				"downloads": info.get("downloads", []),
				"reason": str(hash_check.get("reason", "哈希不匹配")),
			})
			continue
		if local == target_file:
			unchanged.append(target_file)
			continue
		var backup2 := FileUtilsScript.backup_file(target_file)
		if not bool(backup2.get("ok", false)):
			errors.append("无法备份：" + target_file + "（" + str(backup2.get("error", "")) + "）")
			continue
		if not str(backup2.get("backup_path", "")).is_empty():
			backups.append(str(backup2.get("backup_path", "")))
		var copy_result := FileUtilsScript.copy_file_chunked(local, target_file)
		if bool(copy_result.get("ok", false)):
			copied.append(target_file)
		else:
			errors.append("复制失败：%s（%s）" % [rel_path, copy_result.get("error", "")])
	zip.close()
	_emit_progress(progress_cb, 100, "导入完成")
	var deps: Variant = index.get("dependencies", {})
	return {
		"ok": true,
		"error": {},
		"name": str(index.get("name", pack.get_file())),
		"version_id": str(index.get("versionId", "")),
		"minecraft": str(deps.get("minecraft", "")) if deps is Dictionary else "",
		"dependencies": deps,
		"target_dir": game_dir,
		"copied": copied,
		"unchanged": unchanged,
		"backups": backups,
		"missing": missing,
		"errors": errors,
		"warnings": warnings,
		"total": total_steps,
	}


static func _verify_hashes(path: String, hashes: Variant, expected_size: int = -1) -> Dictionary:
	if not (hashes is Dictionary):
		return {"ok": true, "note": ""}
	var sha1 := str(hashes.get("sha1", ""))
	var sha256 := str(hashes.get("sha256", ""))
	var sha512 := str(hashes.get("sha512", ""))
	if not sha1.is_empty():
		var result := FileUtilsScript.hash_file(path, HashingContext.HASH_SHA1)
		if not bool(result.get("ok", false)):
			return {"ok": false, "reason": "无法计算 SHA-1：" + str(result.get("error", "")), "note": ""}
		if str(result.get("hex", "")).to_lower() != sha1.to_lower():
			return {"ok": false, "reason": "SHA-1 不匹配（本地文件可能版本不同）", "note": ""}
		return {"ok": true, "note": ""}
	if not sha256.is_empty():
		var result256 := FileUtilsScript.hash_file(path, HashingContext.HASH_SHA256)
		if not bool(result256.get("ok", false)):
			return {"ok": false, "reason": "无法计算 SHA-256：" + str(result256.get("error", "")), "note": ""}
		if str(result256.get("hex", "")).to_lower() != sha256.to_lower():
			return {"ok": false, "reason": "SHA-256 不匹配（本地文件可能版本不同）", "note": ""}
		return {"ok": true, "note": ""}
	if expected_size > 0:
		var actual := FileUtilsScript.file_size(path)
		if actual != expected_size:
			return {"ok": false, "reason": "文件大小不匹配（%d/%d 字节）" % [actual, expected_size], "note": ""}
		var note := ""
		if not sha512.is_empty():
			note = "整合包仅提供 SHA-512 哈希，引擎内置哈希不支持，已改用文件大小校验。"
		return {"ok": true, "note": note}
	return {"ok": true, "note": "整合包未提供可用哈希或文件大小，已跳过校验。"}


static func _percent(done: int, total: int) -> int:
	if total <= 0:
		return 99
	return clampi(int(round(100.0 * done / total)), 0, 99)


static func _emit_progress(cb: Callable, percent: int, message: String) -> void:
	if cb.is_valid():
		cb.call_deferred(percent, message)


static func _fatal(code: String, ctx: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"error": ErrorInfoScript.make(code, ctx),
		"name": "",
		"copied": [],
		"unchanged": [],
		"backups": [],
		"missing": [],
		"errors": [],
		"warnings": [],
		"total": 0,
	}
