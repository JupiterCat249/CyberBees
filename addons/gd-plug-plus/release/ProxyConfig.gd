class_name ProxyConfig
extends RefCounted

## Global proxy configuration for all network requests.
## Stored as plain-text JSON alongside the encrypted token file.

const _DIR_NAME := "gd-plug-plus"
const _FILE_NAME := "proxy.json"
const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 7897

static var _cache: Dictionary = {}
static var _loaded: bool = false


static func get_config_path() -> String:
	return OS.get_config_dir().path_join(_DIR_NAME).path_join(_FILE_NAME)


static func load_config() -> Dictionary:
	if _loaded:
		return _cache.duplicate()
	var path := get_config_path()
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var text := f.get_as_text()
			f.close()
			var parsed = JSON.parse_string(text)
			if parsed is Dictionary:
				_cache = parsed
				_loaded = true
				return _cache.duplicate()
	_cache = {"enabled": false, "host": DEFAULT_HOST, "port": DEFAULT_PORT}
	_loaded = true
	return _cache.duplicate()


static func save_config(cfg: Dictionary) -> void:
	var dir_path := OS.get_config_dir().path_join(_DIR_NAME)
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var path := get_config_path()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(cfg, "\t"))
		f.close()
	_cache = cfg.duplicate()
	_loaded = true


static func apply_to_http(http: HTTPRequest) -> void:
	var cfg := load_config()
	if cfg.get("enabled", false):
		var host: String = cfg.get("host", DEFAULT_HOST)
		var port: int = int(cfg.get("port", DEFAULT_PORT))
		if not host.is_empty() and port > 0:
			http.set_http_proxy(host, port)
			http.set_https_proxy(host, port)
			return
	http.set_http_proxy("", -1)
	http.set_https_proxy("", -1)


static func get_git_proxy_args() -> Array:
	var cfg := load_config()
	if cfg.get("enabled", false):
		var host: String = cfg.get("host", DEFAULT_HOST)
		var port: int = int(cfg.get("port", DEFAULT_PORT))
		if not host.is_empty() and port > 0:
			return ["-c", "http.proxy=http://%s:%d" % [host, port]]
	return []


static func invalidate_cache() -> void:
	_loaded = false
	_cache = {}
