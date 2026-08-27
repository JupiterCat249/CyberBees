@tool
class_name ReleaseInstallCommand
extends InstallCommand

## Installs from Release: cache check -> hit = direct copy;
## miss = download -> extract -> delete zip -> copy.
## Operates on the main thread via HTTPRequest signals.

var _release_manager: ReleaseManager
var _project_root: String


func _init(repo_name: String, addon_info: Dictionary, rm: ReleaseManager, project_root: String):
	super(repo_name, addon_info)
	_release_manager = rm
	_project_root = project_root


func execute() -> void:
	if _cancelled:
		completed.emit(false, "Cancelled")
		return
	var tag: String = _addon_info.get("installed_tag", "")
	var addon_dir: String = _addon_info.get("addon_dir", "")
	if _release_manager.is_tag_cached(_repo_name, tag):
		if _copy_from_cache(tag, addon_dir):
			completed.emit(true, "")
			return
	progress_updated.emit("Downloading %s %s..." % [_repo_name, tag])
	var url: String = _addon_info.get("url", "")
	var asset_url: String = _addon_info.get("_release_asset_url", "")
	_release_manager.download_completed.connect(
		func(ok: bool, cache_dir: String):
			if ok:
				if _copy_from_cache(tag, addon_dir):
					completed.emit(true, "")
				else:
					completed.emit(false, "Cache empty after download")
			else:
				completed.emit(false, "Download failed"),
		CONNECT_ONE_SHOT
	)
	_release_manager.download_asset(url, _repo_name, tag, asset_url, addon_dir)


func _copy_from_cache(tag: String, addon_dir: String) -> bool:
	var cache_dir = _release_manager.get_cache_dir(_repo_name, tag)
	var src = cache_dir.path_join("addons").path_join(addon_dir.get_file())
	if not DirAccess.dir_exists_absolute(src):
		src = cache_dir.path_join(addon_dir)
	if not DirAccess.dir_exists_absolute(src):
		src = cache_dir
	var dst = _project_root.path_join(addon_dir)
	DirAccess.make_dir_recursive_absolute(dst)
	var copied = GitManager._copy_dir_recursive(src, dst)
	if copied == 0:
		_release_manager.clear_tag_cache(_repo_name, tag)
		return false
	return true
