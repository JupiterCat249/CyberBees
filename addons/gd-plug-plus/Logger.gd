@tool
class_name PlugLogger
extends RefCounted

## Thread-safe global logger with two levels:
##   info()  — UI console + CMD + file  (progress, results, errors)
##   debug() — CMD + file only          (internal details)
##
## File is kept open as a static handle to avoid Windows file-lock contention
## between main thread and worker threads. All I/O is inside the mutex.

const LOG_FILE_PATH = "user://gd-plug-plus-debug.log"

static var _logs: Array[String] = []
static var _log_count: int = 0
static var _mutex: Mutex = Mutex.new()
static var _file: FileAccess = null
static var _session_started: bool = false


static func info(msg: String) -> void:
	_write(msg, false)


static func debug(msg: String) -> void:
	_write(msg, true)


static func _write(msg: String, is_debug: bool) -> void:
	var time_dict = Time.get_time_dict_from_system()
	var time_str = "%02d:%02d:%02d" % [time_dict.hour, time_dict.minute, time_dict.second]
	var entry = "[%s] %s" % [time_str, msg]

	if is_debug:
		print("[gd-plug-plus] [%s] [D] %s" % [time_str, msg])
	else:
		print("[gd-plug-plus] %s" % entry)

	_mutex.lock()

	if not _session_started:
		_session_started = true
		_open_file()
		if _file != null:
			var d = Time.get_datetime_dict_from_system()
			var header = (
				"\n========== SESSION %04d-%02d-%02d %02d:%02d:%02d ==========\n"
				% [d.year, d.month, d.day, d.hour, d.minute, d.second]
			)
			_file.store_string(header)
			var real_path = ProjectSettings.globalize_path(LOG_FILE_PATH)
			_file.store_line("[log-file] path = %s" % real_path)
			_file.flush()
			print("[gd-plug-plus] log file: %s" % real_path)

	if not is_debug:
		_logs.append(entry)
		_log_count = _logs.size()

	var file_entry = "[D] %s" % entry if is_debug else entry
	if _file != null:
		_file.store_line(file_entry)
		_file.flush()
	elif _session_started:
		_open_file()
		if _file != null:
			_file.store_line(file_entry)
			_file.flush()

	_mutex.unlock()


static func get_log_count() -> int:
	_mutex.lock()
	var c = _log_count
	_mutex.unlock()
	return c


static func get_logs_since(from: int) -> Array[String]:
	_mutex.lock()
	var result: Array[String] = []
	for i in range(from, _logs.size()):
		result.append(_logs[i])
	_mutex.unlock()
	return result


static func clear() -> void:
	_mutex.lock()
	_logs.clear()
	_log_count = 0
	_mutex.unlock()


static func _open_file() -> void:
	_file = FileAccess.open(LOG_FILE_PATH, FileAccess.READ_WRITE)
	if _file != null:
		_file.seek_end(0)
		return
	_file = FileAccess.open(LOG_FILE_PATH, FileAccess.WRITE)
