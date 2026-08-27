@tool
class_name ReleaseManager
extends Node

## Facade — the single external entry point for all Release operations.
## Composes TokenStore, ReleaseCache, AssetMatcher, and uses ProviderFactory
## to dispatch to the correct platform.

signal releases_fetched(releases: Array)
signal download_completed(success: bool, cache_dir: String)
signal download_progress(downloaded_bytes: int, total_bytes: int)
signal tags_fetched(tags: Array)

var _token_store: TokenStore = TokenStore.new()
var _cache: ReleaseCache = ReleaseCache.new()
var _http: HTTPRequest
var _current_op: ReleaseOperation
var _current_provider: ReleaseProvider

var _last_error: String = ""
var _last_detected_type: String = ""
var _last_detected_addon_dirs: PackedStringArray = []
var _downloading: bool = false


func _ready():
	_http = HTTPRequest.new()
	_http.download_chunk_size = 65536
	ProxyConfig.apply_to_http(_http)
	add_child(_http)
	_token_store.load_tokens()


func _process(_delta: float) -> void:
	if not _downloading:
		return
	var downloaded := _http.get_downloaded_bytes()
	var total := _http.get_body_size()
	download_progress.emit(downloaded, total)


func fetch_releases(url: String) -> void:
	PlugLogger.debug("ReleaseManager.fetch_releases: %s" % url)
	_current_provider = ProviderFactory.create(url)
	if _current_provider == null:
		PlugLogger.debug("ReleaseManager: no provider for URL, emitting empty")
		releases_fetched.emit([])
		return
	PlugLogger.debug("ReleaseManager: provider=%s" % _current_provider.get_platform_key())
	_current_op = FetchReleasesOp.new(_current_provider, _token_store, _http)
	_current_op.releases_fetched.connect(func(r):
		PlugLogger.debug("ReleaseManager: releases_fetched count=%d" % r.size())
		_current_op = null
		_current_provider = null
		releases_fetched.emit(r)
	, CONNECT_ONE_SHOT)
	PlugLogger.debug("ReleaseManager: calling op.execute")
	_current_op.execute({"repo_url": url})
	PlugLogger.debug("ReleaseManager: op.execute returned")


func download_asset(
	url: String, repo_name: String, tag: String, asset_url: String, expected_addon_dir: String = ""
) -> void:
	_last_error = ""
	_last_detected_type = ""
	_last_detected_addon_dirs = PackedStringArray()
	PlugLogger.debug(
		"ReleaseManager.download_asset: repo=%s tag=%s asset_url=%s addon_dir=%s"
		% [repo_name, tag, asset_url, expected_addon_dir]
	)
	if repo_name.strip_edges().is_empty() or tag.strip_edges().is_empty():
		PlugLogger.info(
			"Release download skipped: repo_name or tag empty"
		)
		_last_error = "ERR_RELEASE_INVALID_PARAMS"
		download_completed.emit(false, "")
		return
	if asset_url.is_empty():
		PlugLogger.info(
			"Release download skipped: asset_url empty for %s %s"
			% [repo_name, tag]
		)
		_last_error = "ERR_RELEASE_ASSET_URL_EMPTY"
		download_completed.emit(false, "")
		return
	if _cache.is_cached(repo_name, tag):
		var cached_dir = _cache.get_dir(repo_name, tag)
		PlugLogger.info("Release cache hit: %s %s → %s" % [repo_name, tag, cached_dir])
		inspect_cache_dir(cached_dir)
		download_completed.emit(true, cached_dir)
		return
	_current_provider = ProviderFactory.create(url)
	if _current_provider == null:
		PlugLogger.info("Release download failed: unsupported platform URL %s" % url)
		_last_error = "ERR_RELEASE_UNSUPPORTED_PLATFORM"
		download_completed.emit(false, "")
		return
	var cache_dir = _cache.get_dir(repo_name, tag)
	var zip_path = cache_dir + ".zip"
	PlugLogger.debug("ReleaseManager: cache_dir=%s zip_path=%s" % [cache_dir, zip_path])
	DirAccess.make_dir_recursive_absolute(cache_dir)
	PlugLogger.info("Downloading release asset: %s" % asset_url)
	_downloading = true
	_current_op = DownloadAssetOp.new(_current_provider, _token_store, _http)
	_current_op.download_completed.connect(
		func(ok: bool, path: String):
			_downloading = false
			_current_op = null
			_current_provider = null
			if ok:
				PlugLogger.debug(
					"ReleaseManager: download OK, extracting %s → %s"
					% [path, cache_dir]
				)
				var dl_path: String = path
				var cache_d: String = cache_dir
				var exp_dir: String = expected_addon_dir
				WorkerThreadPool.add_task(func():
					var success = _extract_and_cleanup(
						dl_path, cache_d, exp_dir
					)
					if success:
						PlugLogger.info(
							"Release extracted to %s" % cache_d
						)
					else:
						PlugLogger.info(
							"Release extraction failed: %s" % dl_path
						)
					call_deferred(
						"_emit_download_completed", success, cache_d
					)
				)
			else:
				PlugLogger.info("Release download failed for %s %s" % [repo_name, tag])
				if _last_error.is_empty():
					_last_error = "ERR_RELEASE_DOWNLOAD_FAILED"
				download_completed.emit(false, ""),
		CONNECT_ONE_SHOT
	)
	_current_op.execute({"asset_url": asset_url, "save_path": zip_path})


func get_tags(url: String) -> void:
	fetch_releases(url)
	releases_fetched.connect(
		func(release_list: Array):
			var tags: Array = []
			for r in release_list:
				(
					tags
					. append(
						{
							"tag_name": r.get("tag_name", ""),
							"name": r.get("name", ""),
							"created_at": r.get("created_at", ""),
						}
					)
				)
			tags_fetched.emit(tags),
		CONNECT_ONE_SHOT
	)


func is_tag_cached(repo_name: String, tag: String) -> bool:
	return _cache.is_cached(repo_name, tag)


func get_cache_dir(repo_name: String, tag: String) -> String:
	return _cache.get_dir(repo_name, tag)


func clear_repo_cache(repo_name: String) -> void:
	_cache.clear(repo_name)


func clear_tag_cache(repo_name: String, tag: String) -> void:
	_cache.clear_tag(repo_name, tag)


## Error code from the most recent failed download/extract/validate, or "".
## Translation key; callers should tr() it before showing to users.
func get_last_error() -> String:
	return _last_error


## Detected addon type from the most recent successful extract ("plugin" / "extension" / "").
func get_last_detected_type() -> String:
	return _last_detected_type


## Detected addon directories (relative to cache_dir, e.g. "addons/foo") from last extract.
func get_last_detected_addon_dirs() -> PackedStringArray:
	return _last_detected_addon_dirs


## Exposes the underlying TokenStore so the AddonManager UI can run pre-checks
## (and the Token Settings dialog can read/write tokens) without holding its
## own copy. There is a single TokenStore instance for the whole release stack.
func get_token_store() -> TokenStore:
	return _token_store


func _emit_download_completed(success: bool, cache_dir: String) -> void:
	download_completed.emit(success, cache_dir)


func cancel() -> void:
	_downloading = false
	_http.cancel_request()
	_current_op = null
	_current_provider = null


func apply_proxy() -> void:
	ProxyConfig.apply_to_http(_http)


# ---------------------------------------------------------------------------
# Zip extraction + normalization + cleanup
# ---------------------------------------------------------------------------


func _extract_and_cleanup(zip_path: String, cache_dir: String, expected_addon_dir: String) -> bool:
	PlugLogger.debug(
		"_extract_and_cleanup: zip=%s cache=%s addon_dir=%s"
		% [zip_path, cache_dir, expected_addon_dir]
	)
	if not FileAccess.file_exists(zip_path):
		PlugLogger.info("Extraction failed: zip file not found at %s" % zip_path)
		_last_error = "ERR_RELEASE_ZIP_MISSING"
		return false
	var zip_size := FileAccess.open(zip_path, FileAccess.READ)
	var zip_bytes: int = zip_size.get_length() if zip_size else 0
	if zip_size:
		zip_size.close()
	PlugLogger.debug("_extract_and_cleanup: zip file size = %d bytes" % zip_bytes)
	var reader = ZIPReader.new()
	var open_err = reader.open(zip_path)
	if open_err != OK:
		PlugLogger.info("Extraction failed: cannot open zip (error=%d) %s" % [open_err, zip_path])
		_last_error = "ERR_RELEASE_ZIP_OPEN_FAILED"
		DirAccess.remove_absolute(zip_path)
		return false
	var files = reader.get_files()
	PlugLogger.debug("_extract_and_cleanup: zip contains %d entries" % files.size())
	if files.size() > 0:
		PlugLogger.debug(
			"_extract_and_cleanup: first entries: %s"
			% str(files.slice(0, mini(5, files.size())))
		)

	var inspection: Dictionary = _inspect_archive_contents(files)
	PlugLogger.debug(
		(
			"_extract_and_cleanup: inspection ok=%s type=%s plugin_cfgs=%d gdextensions=%d"
			% [
				str(inspection.get("ok", false)),
				inspection.get("type", ""),
				inspection.get("plugin_cfg_paths", PackedStringArray()).size(),
				inspection.get("gdextension_paths", PackedStringArray()).size(),
			]
		)
	)
	if not inspection.get("ok", false):
		reader.close()
		var reason: String = inspection.get("reason", "ERR_RELEASE_NO_GODOT_CONTENT")
		PlugLogger.info(
			(
				"Release archive rejected: %s (no plugin.cfg or .gdextension found, %d files)"
				% [reason, files.size()]
			)
		)
		_last_error = reason
		DirAccess.remove_absolute(zip_path)
		# Clean up the empty cache dir so a re-download attempt works cleanly.
		if DirAccess.dir_exists_absolute(cache_dir):
			var gm = load("res://addons/gd-plug-plus/GitManager.gd")
			if gm and gm.has_method("delete_directory"):
				gm.delete_directory(cache_dir)
		return false

	var extracted_count := 0
	for file_path in files:
		if file_path.ends_with("/"):
			DirAccess.make_dir_recursive_absolute(cache_dir.path_join(file_path))
			continue
		var parent = cache_dir.path_join(file_path.get_base_dir())
		DirAccess.make_dir_recursive_absolute(parent)
		var data = reader.read_file(file_path)
		var f = FileAccess.open(cache_dir.path_join(file_path), FileAccess.WRITE)
		if f:
			f.store_buffer(data)
			f.close()
			extracted_count += 1
		else:
			PlugLogger.debug("_extract_and_cleanup: failed to write %s" % cache_dir.path_join(file_path))
	reader.close()
	PlugLogger.info("Extracted %d files from release archive" % extracted_count)

	_last_detected_type = inspection.get("type", "")
	_last_detected_addon_dirs = inspection.get("addon_dirs", PackedStringArray())

	_normalize_extracted(cache_dir, expected_addon_dir)
	DirAccess.remove_absolute(zip_path)
	return true


## Scans the given zip file list for Godot addon markers (plugin.cfg / *.gdextension).
## Returns: {ok: bool, type: String, plugin_cfg_paths, gdextension_paths, addon_dirs, reason}
## - `ok` is true when at least one plugin.cfg or .gdextension is present.
## - `type` is "plugin" if any plugin.cfg is found, otherwise "extension" when .gdextension exists.
## - `addon_dirs` are the unique parent directories of those markers (e.g. "addons/foo/bar").
static func _inspect_archive_contents(files: PackedStringArray) -> Dictionary:
	var plugin_cfgs: PackedStringArray = PackedStringArray()
	var gdexts: PackedStringArray = PackedStringArray()
	var addon_dirs_set: Dictionary = {}
	for f in files:
		if f.ends_with("/"):
			continue
		var base: String = f.get_file()
		if base == "plugin.cfg":
			plugin_cfgs.append(f)
			addon_dirs_set[f.get_base_dir()] = true
		elif base.get_extension() == "gdextension":
			gdexts.append(f)
			addon_dirs_set[f.get_base_dir()] = true
	var ok: bool = not plugin_cfgs.is_empty() or not gdexts.is_empty()
	var detected_type: String = ""
	if not plugin_cfgs.is_empty():
		detected_type = "plugin"
	elif not gdexts.is_empty():
		detected_type = "extension"
	var dirs: PackedStringArray = PackedStringArray(addon_dirs_set.keys())
	return {
		"ok": ok,
		"type": detected_type,
		"plugin_cfg_paths": plugin_cfgs,
		"gdextension_paths": gdexts,
		"addon_dirs": dirs,
		"reason": "" if ok else "ERR_RELEASE_NO_GODOT_CONTENT",
	}


## Walks an already-extracted cache dir to detect type (used on cache-hit path).
## Public so callers (e.g. AddonManager release tag switch) can refresh
## `_last_detected_type` for the new tag's content before reading metadata.
func inspect_cache_dir(cache_dir: String) -> void:
	if not DirAccess.dir_exists_absolute(cache_dir):
		return
	var scanned = GitManager.scan_local_addons(cache_dir)
	var dirs: PackedStringArray = PackedStringArray()
	var has_plugin := false
	var has_ext := false
	for a in scanned:
		var atype: String = a.get("type", "")
		if atype == "editor_plugin":
			has_plugin = true
		elif atype == "gdextension":
			has_ext = true
		dirs.append(a.get("addon_dir", ""))
	if has_plugin:
		_last_detected_type = "plugin"
	elif has_ext:
		_last_detected_type = "extension"
	else:
		_last_detected_type = ""
	_last_detected_addon_dirs = dirs


func _normalize_extracted(extract_dir: String, expected_addon_dir: String) -> void:
	PlugLogger.debug(
		"_normalize_extracted: dir=%s expected_addon_dir=%s"
		% [extract_dir, expected_addon_dir]
	)
	if DirAccess.dir_exists_absolute(extract_dir.path_join("addons")):
		PlugLogger.debug("_normalize_extracted: addons/ found at top level, no normalization needed")
		return

	var dir = DirAccess.open(extract_dir)
	if dir == null:
		PlugLogger.debug("_normalize_extracted: cannot open extract_dir %s" % extract_dir)
		return
	dir.list_dir_begin()
	var fname = dir.get_next()
	var single_subdir := ""
	var count := 0
	while not fname.is_empty():
		if dir.current_is_dir() and not fname.begins_with("."):
			single_subdir = fname
			count += 1
		fname = dir.get_next()
	dir.list_dir_end()
	PlugLogger.debug("_normalize_extracted: found %d subdirs, single=%s" % [count, single_subdir])

	if (
		count == 1
		and DirAccess.dir_exists_absolute(extract_dir.path_join(single_subdir).path_join("addons"))
	):
		PlugLogger.debug("_normalize_extracted: unwrapping %s/addons/ to top level" % single_subdir)
		var src_addons = extract_dir.path_join(single_subdir).path_join("addons")
		var dst_addons = extract_dir.path_join("addons")
		_move_dir(src_addons, dst_addons)
		var sub = DirAccess.open(extract_dir.path_join(single_subdir))
		if sub:
			sub.list_dir_begin()
			var sf = sub.get_next()
			while not sf.is_empty():
				if not sub.current_is_dir():
					sub.rename(
						extract_dir.path_join(single_subdir).path_join(sf),
						extract_dir.path_join(sf)
					)
				sf = sub.get_next()
			sub.list_dir_end()
		var remaining = DirAccess.open(extract_dir.path_join(single_subdir))
		if remaining:
			remaining.list_dir_begin()
			var r = remaining.get_next()
			var has_content := false
			while not r.is_empty():
				if not r.begins_with("."):
					has_content = true
					break
				r = remaining.get_next()
			remaining.list_dir_end()
			if not has_content:
				GitManager.delete_directory(extract_dir.path_join(single_subdir))
		return

	if not expected_addon_dir.is_empty():
		var target = extract_dir.path_join(expected_addon_dir)
		PlugLogger.debug("_normalize_extracted: fallback — moving to %s" % target)
		if not DirAccess.dir_exists_absolute(target):
			DirAccess.make_dir_recursive_absolute(target)
			var root = DirAccess.open(extract_dir)
			if root:
				root.list_dir_begin()
				var rf = root.get_next()
				while not rf.is_empty():
					var rpath = extract_dir.path_join(rf)
					if rf != expected_addon_dir.split("/")[0]:
						if root.current_is_dir():
							_move_dir(rpath, target.path_join(rf))
						else:
							root.rename(rpath, target.path_join(rf))
					rf = root.get_next()
				root.list_dir_end()
	else:
		PlugLogger.debug(
			"_normalize_extracted: no addons/, "
			+ "no expected_addon_dir, left as-is"
		)


func _move_dir(from: String, to: String) -> void:
	GitManager._copy_dir_recursive(from, to)
	GitManager.delete_directory(from)
