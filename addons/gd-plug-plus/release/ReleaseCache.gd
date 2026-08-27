@tool
class_name ReleaseCache
extends RefCounted

## Manages the on-disk cache of extracted release directories.
## Only extracted directory trees are cached — zip files are deleted after extraction.


static func get_cache_root() -> String:
	var base = OS.get_temp_dir().path_join("gd-plug-plus").path_join("releases")
	if not DirAccess.dir_exists_absolute(base):
		DirAccess.make_dir_recursive_absolute(base)
	return base


func is_cached(repo_name: String, tag: String) -> bool:
	var path = get_dir(repo_name, tag)
	if not DirAccess.dir_exists_absolute(path):
		return false
	var dir = DirAccess.open(path)
	if dir == null:
		return false
	dir.list_dir_begin()
	var has_content := false
	var fname := dir.get_next()
	while not fname.is_empty():
		if not fname.begins_with("."):
			has_content = true
			break
		fname = dir.get_next()
	dir.list_dir_end()
	return has_content


func get_dir(repo_name: String, tag: String) -> String:
	return get_cache_root().path_join(repo_name).path_join(tag)


func clear(repo_name: String) -> void:
	if repo_name.strip_edges().is_empty():
		return
	var path = get_cache_root().path_join(repo_name)
	if DirAccess.dir_exists_absolute(path):
		GitManager.delete_directory(path)


func clear_tag(repo_name: String, tag: String) -> void:
	if repo_name.strip_edges().is_empty():
		return
	if tag.strip_edges().is_empty():
		return
	var path = get_dir(repo_name, tag)
	if DirAccess.dir_exists_absolute(path):
		GitManager.delete_directory(path)
