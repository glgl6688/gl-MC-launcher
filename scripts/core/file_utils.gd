class_name FileUtils
extends RefCounted
## 文件与路径工具。所有对外路径统一使用正斜杠 "/"。
## 大文件复制使用分块读写，调用方应把它放在后台线程中执行。

const CHUNK_SIZE := 1048576


static func normalize(path: String) -> String:
	var p := path.replace("\\", "/")
	if p.is_empty():
		return p
	while p.length() > 1 and p.ends_with("/") and not p.ends_with(":/"):
		p = p.substr(0, p.length() - 1)
	return p


static func to_global(path: String) -> String:
	var p := normalize(path)
	if p.begins_with("user://") or p.begins_with("res://"):
		p = ProjectSettings.globalize_path(p)
	return normalize(p)


static func join(base: String, relative: String) -> String:
	if base.is_empty():
		return normalize(relative)
	if relative.is_empty():
		return normalize(base)
	return normalize(normalize(base).path_join(normalize(relative)))


static func ensure_dir(path: String) -> Error:
	var p := normalize(path)
	if p.is_empty():
		return ERR_INVALID_PARAMETER
	if DirAccess.dir_exists_absolute(p):
		return OK
	return DirAccess.make_dir_recursive_absolute(p)


static func ensure_dirs(paths: PackedStringArray) -> Error:
	for p in paths:
		var err := ensure_dir(p)
		if err != OK:
			return err
	return OK


static func is_file(path: String) -> bool:
	return FileAccess.file_exists(normalize(path))


static func is_dir(path: String) -> bool:
	return DirAccess.dir_exists_absolute(normalize(path))


static func file_size(path: String) -> int:
	var f := FileAccess.open(normalize(path), FileAccess.READ)
	if f == null:
		return -1
	var size := int(f.get_length())
	f.close()
	return size


static func read_text(path: String) -> Dictionary:
	var p := normalize(path)
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {"ok": false, "text": "", "error": error_string(FileAccess.get_open_error())}
	var text := f.get_as_text()
	f.close()
	return {"ok": true, "text": text, "error": ""}


static func write_text(path: String, text: String) -> Dictionary:
	var p := normalize(path)
	var err := ensure_dir(p.get_base_dir())
	if err != OK:
		return {"ok": false, "error": error_string(err)}
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": error_string(FileAccess.get_open_error())}
	f.store_string(text)
	f.flush()
	var werr := f.get_error()
	f.close()
	return {"ok": werr == OK, "error": "" if werr == OK else error_string(werr)}


static func write_bytes(path: String, bytes: PackedByteArray) -> Dictionary:
	var p := normalize(path)
	var err := ensure_dir(p.get_base_dir())
	if err != OK:
		return {"ok": false, "error": error_string(err)}
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": error_string(FileAccess.get_open_error())}
	f.store_buffer(bytes)
	f.flush()
	var werr := f.get_error()
	f.close()
	return {"ok": werr == OK, "error": "" if werr == OK else error_string(werr)}


## 分块复制文件。progress 回调参数为 (已复制字节, 总字节)，可能从后台线程触发，
## 调用方若要更新 UI 必须自行 call_deferred。
static func copy_file_chunked(source: String, target: String, progress: Callable = Callable(), chunk_size: int = CHUNK_SIZE) -> Dictionary:
	var src_path := normalize(source)
	var dst_path := normalize(target)
	if not FileAccess.file_exists(src_path):
		return {"ok": false, "error": "源文件不存在", "copied": 0, "total": 0}
	var mk := ensure_dir(dst_path.get_base_dir())
	if mk != OK:
		return {"ok": false, "error": "无法创建目标目录：" + error_string(mk), "copied": 0, "total": 0}
	var src := FileAccess.open(src_path, FileAccess.READ)
	if src == null:
		return {"ok": false, "error": error_string(FileAccess.get_open_error()), "copied": 0, "total": 0}
	var total := int(src.get_length())
	var dst := FileAccess.open(dst_path, FileAccess.WRITE)
	if dst == null:
		src.close()
		return {"ok": false, "error": error_string(FileAccess.get_open_error()), "copied": 0, "total": total}
	var copied := 0
	var step := maxi(4096, chunk_size)
	while copied < total:
		var buf := src.get_buffer(step)
		if buf.is_empty():
			break
		dst.store_buffer(buf)
		copied += buf.size()
		if progress.is_valid():
			progress.call(copied, total)
		if dst.get_error() != OK:
			break
	var werr := dst.get_error()
	src.close()
	dst.flush()
	dst.close()
	if copied != total or werr != OK:
		return {
			"ok": false,
			"error": "写入不完整（%d/%d 字节）%s" % [copied, total, "" if werr == OK else "：" + error_string(werr)],
			"copied": copied,
			"total": total,
		}
	return {"ok": true, "error": "", "copied": copied, "total": total}


## 若目标文件存在，先重命名为 .bak（若 .bak 已存在则追加时间戳）。
static func backup_file(path: String) -> Dictionary:
	var p := normalize(path)
	if not FileAccess.file_exists(p):
		return {"ok": true, "backup_path": ""}
	var backup := p + ".bak"
	if FileAccess.file_exists(backup):
		var stamp := Time.get_datetime_string_from_system(false, true)
		stamp = stamp.replace("-", "").replace(":", "").replace("T", "-")
		backup = "%s.%s.bak" % [p, stamp]
	var err := DirAccess.rename_absolute(p, backup)
	if err != OK:
		return {"ok": false, "backup_path": "", "error": error_string(err)}
	return {"ok": true, "backup_path": backup}


static func hash_file(path: String, algorithm: int = HashingContext.HASH_SHA256) -> Dictionary:
	var p := normalize(path)
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {"ok": false, "hex": "", "error": error_string(FileAccess.get_open_error())}
	var ctx := HashingContext.new()
	var start_err := ctx.start(algorithm)
	if start_err != OK:
		f.close()
		return {"ok": false, "hex": "", "error": error_string(start_err)}
	var total := int(f.get_length())
	var copied := 0
	while copied < total:
		var buf := f.get_buffer(CHUNK_SIZE)
		if buf.is_empty():
			break
		ctx.update(buf)
		copied += buf.size()
	f.close()
	if copied != total:
		return {"ok": false, "hex": "", "error": "读取不完整"}
	return {"ok": true, "hex": ctx.finish().hex_encode(), "error": ""}


## 仅允许相对路径，拒绝绝对路径、盘符、.. 越界与空路径，防止压缩包路径穿越。
static func is_safe_relative(relative: String) -> bool:
	var p := normalize(relative)
	if p.is_empty() or p.begins_with("/") or p.contains(":"):
		return false
	for part in p.split("/", false):
		if part == ".." or part == ".":
			return false
	return true


static func extension_of(path: String) -> String:
	return normalize(path).get_extension().to_lower()


static func list_dirs(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(normalize(path))
	if dir == null:
		return out
	for name in dir.get_directories():
		out.append(normalize(name))
	return out


static func list_files(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(normalize(path))
	if dir == null:
		return out
	for name in dir.get_files():
		out.append(normalize(name))
	return out


static func join_all(parts: Array) -> String:
	var result := ""
	for part in parts:
		if result.is_empty():
			result = normalize(str(part))
		else:
			result = join(result, str(part))
	return result
