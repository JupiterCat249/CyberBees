@tool
class_name FetchReleasesOp
extends ReleaseOperation

## Fetches the releases list from a platform's API and normalizes the result.
## For Gitee, also fetches attach_files for each release (sequential HTTP calls).

signal releases_fetched(releases: Array)

var _releases: Array = []
var _attach_queue: Array = []
var _repo_url: String
var _current_attach_idx: int = -1


func _build_url(context: Dictionary) -> String:
	_repo_url = context.get("repo_url", "")
	return _provider.build_releases_url(_repo_url)


func _on_response(
	result: int, code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	PlugLogger.debug("FetchReleasesOp: result=%d code=%d body_size=%d" % [result, code, body.size()])
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		PlugLogger.debug("FetchReleasesOp: HTTP failed, emitting empty")
		releases_fetched.emit([])
		return
	var text = body.get_string_from_utf8()
	var json = JSON.parse_string(text)
	if json is not Array:
		PlugLogger.debug("FetchReleasesOp: response is not Array, emitting empty")
		releases_fetched.emit([])
		return
	var releases: Array = []
	for raw in json:
		releases.append(_provider.normalize_release(raw))
	PlugLogger.debug("FetchReleasesOp: parsed %d releases" % releases.size())
	_log_releases(releases)

	if _provider.needs_attach_files_fetch():
		_releases = releases
		_attach_queue.clear()
		for i in releases.size():
			var rid: int = releases[i].get("_release_id", 0)
			if rid > 0:
				_attach_queue.append({"idx": i, "release_id": rid})
		if not _attach_queue.is_empty():
			PlugLogger.debug("FetchReleasesOp: fetching attach_files for %d releases" % _attach_queue.size())
			_fetch_next_attach()
			return

	releases_fetched.emit(releases)


func _fetch_next_attach() -> void:
	if _attach_queue.is_empty():
		PlugLogger.debug("FetchReleasesOp: all attach_files fetched, emitting releases")
		_log_releases(_releases)
		releases_fetched.emit(_releases)
		return

	var entry: Dictionary = _attach_queue.pop_front()
	var url: String = _provider.build_attach_files_url(_repo_url, entry["release_id"])
	var token := _token_store.get_token(_provider.get_platform_key())
	url = _provider.apply_token_to_url(url, token)
	_current_attach_idx = entry["idx"]

	PlugLogger.debug("FetchReleasesOp: GET attach_files release_id=%d" % entry["release_id"])
	_http.request_completed.connect(_on_attach_response, CONNECT_ONE_SHOT)
	var headers := _dict_to_headers(_provider.get_api_headers(token))
	var err := _http.request(url, headers)
	if err != OK:
		PlugLogger.debug("FetchReleasesOp: attach_files request failed err=%d" % err)
		if _http.request_completed.is_connected(_on_attach_response):
			_http.request_completed.disconnect(_on_attach_response)
		_fetch_next_attach()


func _on_attach_response(
	result: int, code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	var release_idx := _current_attach_idx
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		PlugLogger.debug("FetchReleasesOp: attach_files HTTP %d/%d, skipping" % [result, code])
		_fetch_next_attach()
		return
	var json = JSON.parse_string(body.get_string_from_utf8())
	if json is not Array:
		PlugLogger.debug("FetchReleasesOp: attach_files response not Array, skipping")
		_fetch_next_attach()
		return
	if (json as Array).is_empty():
		_fetch_next_attach()
		return

	var release: Dictionary = _releases[release_idx]
	var rid: int = release.get("_release_id", 0)
	var assets: Array = release.get("assets", [])
	for af in json:
		var af_id: int = af.get("id", 0)
		var dl_url: String = _provider.build_attach_download_url(_repo_url, rid, af_id)
		var asset := {
			"name": af.get("name", ""),
			"size": af.get("size", 0),
			"browser_download_url": dl_url,
			"type": "attachment",
		}
		assets.append(asset)
		PlugLogger.debug(
			"FetchReleasesOp: attach_file id=%d name=%s size=%d url=%s"
			% [af_id, asset["name"], asset["size"], dl_url]
		)
	release["assets"] = assets
	_fetch_next_attach()


func _log_releases(releases: Array) -> void:
	for i in mini(releases.size(), 5):
		var rel: Dictionary = releases[i]
		var tag_str: String = rel.get("tag_name", "?")
		var assets_arr: Array = rel.get("assets", [])
		var lines: PackedStringArray = [
			"  tag=%s  name=%s  prerelease=%s  assets=%d"
			% [
				tag_str,
				rel.get("name", ""),
				rel.get("prerelease", false),
				assets_arr.size()
			]
		]
		for j in mini(assets_arr.size(), 6):
			var a: Dictionary = assets_arr[j]
			lines.append(
				"    [%d] %s  type=%s  size=%d  url=%s"
				% [
					j,
					a.get("name", ""),
					a.get("type", "attachment"),
					a.get("size", -1),
					a.get("browser_download_url", "")
				]
			)
		if assets_arr.size() > 6:
			lines.append("    ... +%d more assets" % (assets_arr.size() - 6))
		PlugLogger.debug("FetchReleasesOp: release[%d]:\n%s" % [i, "\n".join(lines)])
