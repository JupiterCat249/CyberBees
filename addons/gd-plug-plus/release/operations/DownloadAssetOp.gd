@tool
class_name DownloadAssetOp
extends ReleaseOperation

## Downloads a single release asset binary to a local path.

signal download_completed(success: bool, filepath: String)

var _save_path: String


func _build_url(context: Dictionary) -> String:
	_save_path = context.get("save_path", "")
	return context.get("asset_url", "")


func _get_headers(token: String) -> Dictionary:
	return _provider.get_download_headers(token)


func _on_response(
	result: int, code: int, headers: PackedStringArray, body: PackedByteArray
) -> void:
	PlugLogger.debug(
		"DownloadAssetOp._on_response: result=%d code=%d body_size=%d save_path=%s"
		% [result, code, body.size(), _save_path]
	)
	var content_type := ""
	for h in headers:
		var lower = h.to_lower()
		if lower.begins_with("content-type"):
			content_type = h
			break
	PlugLogger.debug("DownloadAssetOp: Content-Type: %s" % content_type)
	if headers.size() > 0:
		PlugLogger.debug(
			"DownloadAssetOp: response headers (%d):\n  %s"
			% [headers.size(), "\n  ".join(headers)]
		)
	if result != HTTPRequest.RESULT_SUCCESS:
		PlugLogger.info("Release download HTTP error: result=%d (not RESULT_SUCCESS)" % result)
		download_completed.emit(false, "")
		return
	if code != 200:
		PlugLogger.info("Release download failed: HTTP %d" % code)
		if body.size() > 0 and body.size() < 2048:
			PlugLogger.debug(
				"DownloadAssetOp: error body: %s" % body.get_string_from_utf8().left(500)
			)
		download_completed.emit(false, "")
		return
	if body.is_empty():
		PlugLogger.info("Release download failed: empty response body")
		download_completed.emit(false, "")
		return

	var is_zip := body.size() >= 4 and body[0] == 0x50 and body[1] == 0x4B
	var is_html := false
	if body.size() >= 15:
		var head_str := body.slice(0, mini(body.size(), 256)).get_string_from_utf8().to_lower()
		is_html = "<html" in head_str or "<!doctype" in head_str
	PlugLogger.debug(
		"DownloadAssetOp: body magic: [0x%02X 0x%02X 0x%02X 0x%02X] is_zip=%s is_html=%s"
		% [
			body[0] if body.size() > 0 else 0,
			body[1] if body.size() > 1 else 0,
			body[2] if body.size() > 2 else 0,
			body[3] if body.size() > 3 else 0,
			is_zip,
			is_html,
		]
	)
	if is_html:
		PlugLogger.info(
			"Release download failed: server returned HTML instead of binary (likely a redirect/login page)"
		)
		PlugLogger.debug(
			"DownloadAssetOp: HTML body preview:\n%s"
			% body.slice(0, mini(body.size(), 1024)).get_string_from_utf8()
		)
		download_completed.emit(false, "")
		return

	DirAccess.make_dir_recursive_absolute(_save_path.get_base_dir())
	var f = FileAccess.open(_save_path, FileAccess.WRITE)
	if f == null:
		var err = FileAccess.get_open_error()
		PlugLogger.info("Release download: cannot write to %s (error=%d)" % [_save_path, err])
		download_completed.emit(false, "")
		return
	f.store_buffer(body)
	f.close()
	PlugLogger.info("Release asset saved: %s (%d bytes)" % [_save_path, body.size()])
	download_completed.emit(true, _save_path)
