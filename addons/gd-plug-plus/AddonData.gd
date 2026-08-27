# gdlint:disable=max-public-methods
class_name AddonData
extends RefCounted

## Unified data layer for addons.json.
## Manages plugin declarations, version info, and install state.
##
## Schema: { schema_version, repos: { repo_name: { url, plugins: [...] } } }
## Version fields (branch/tag/commit) are per-plugin, not per-repo.

const _GM = preload("res://addons/gd-plug-plus/GitManager.gd")

const ADDONS_JSON_PATH = "res://addons/gd-plug-plus/addons.json"
const SCHEMA_VERSION = 1
const _DOMAIN_NAME = "gd-plug-plus"

var _data: Dictionary = {}


func _init():
	_data = _default_data()


static func _default_data() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "repos": {}}


# ---------------------------------------------------------------------------
# Load / Save
# ---------------------------------------------------------------------------


func load_data() -> Error:
	if not FileAccess.file_exists(ADDONS_JSON_PATH):
		_data = _default_data()
		return ERR_FILE_NOT_FOUND
	var file = FileAccess.open(ADDONS_JSON_PATH, FileAccess.READ)
	if file == null:
		_data = _default_data()
		return ERR_CANT_OPEN
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		_data = _default_data()
		return ERR_PARSE_ERROR
	if not json.data is Dictionary:
		_data = _default_data()
		return ERR_INVALID_DATA
	_data = json.data
	if not _data.has("schema_version"):
		_data["schema_version"] = SCHEMA_VERSION
	if not _data.has("repos"):
		_data["repos"] = {}
	return OK


func save_data() -> Error:
	var global_dir = ProjectSettings.globalize_path(ADDONS_JSON_PATH.get_base_dir())
	if not DirAccess.dir_exists_absolute(global_dir):
		DirAccess.make_dir_recursive_absolute(global_dir)
	var file = FileAccess.open(ADDONS_JSON_PATH, FileAccess.WRITE)
	if file == null:
		return ERR_CANT_CREATE
	file.store_string(JSON.stringify(_data, "\t"))
	file.close()
	return OK


# ---------------------------------------------------------------------------
# Repo CRUD
# ---------------------------------------------------------------------------


func get_repos() -> Dictionary:
	return _data.get("repos", {})


func has_repo(repo_name: String) -> bool:
	return _data.get("repos", {}).has(repo_name)


func get_repo(repo_name: String) -> Dictionary:
	return _data.get("repos", {}).get(repo_name, {})


func set_repo(repo_name: String, repo_data: Dictionary) -> void:
	if not _data.has("repos"):
		_data["repos"] = {}
	_data["repos"][repo_name] = repo_data


func remove_repo(repo_name: String) -> bool:
	if not _data.has("repos"):
		return false
	return _data["repos"].erase(repo_name)


## Create a repo entry from search results.
## All plugins default to the given branch, installed = false.
## For release-sourced addons, pass _from_release / _release_tag / _release_asset_url in dp.
func add_repo_from_search(
	repo_name: String, url: String, found_addons: Array, default_branch: String = ""
) -> void:
	var repo: Dictionary = {"url": url, "addons": []}
	for dp in found_addons:
		var addon: Dictionary = {
			"name": dp.get("name", ""),
			"description": dp.get("description", ""),
			"type": _normalize_type(dp.get("type", "")),
			"addon_dir": dp.get("addon_dir", dp.get("plugin_dir", "")),
			"version": dp.get("version", ""),
			"author": dp.get("author", ""),
			"installed": false,
		}
		if dp.get("_from_release", false):
			addon["installed_from"] = "release"
			addon["installed_tag"] = dp.get("_release_tag", "")
			var asset_filename = dp.get("_release_asset_filename", "")
			if not asset_filename.is_empty():
				addon["installed_asset_filename"] = asset_filename
		elif not default_branch.is_empty():
			addon["branch"] = default_branch
		repo["addons"].append(addon)
	set_repo(repo_name, repo)


# ---------------------------------------------------------------------------
# Plugin-level queries
# ---------------------------------------------------------------------------


func get_addons(repo_name: String) -> Array:
	return get_repo(repo_name).get("addons", [])


func find_addon(repo_name: String, addon_dir: String) -> Dictionary:
	for p in get_addons(repo_name):
		if p.get("addon_dir", "") == addon_dir:
			return p
	return {}


func get_installed_addons(repo_name: String) -> Array:
	var result: Array = []
	for p in get_addons(repo_name):
		if p.get("installed", false):
			result.append(p)
	return result


## Get all repos + plugins as a flat list for the installed tree UI.
## Each entry has repo_name, url, renames injected.
func get_all_repos_for_ui() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for repo_name in get_repos():
		var repo = get_repo(repo_name)
		var entry: Dictionary = {
			"repo_name": repo_name,
			"url": repo.get("url", ""),
			"addons": repo.get("addons", []),
		}
		result.append(entry)
	return result


# ---------------------------------------------------------------------------
# Plugin-level mutations
# ---------------------------------------------------------------------------


func set_addon_installed(repo_name: String, addon_dir: String, installed: bool) -> void:
	for p in get_addons(repo_name):
		if p.get("addon_dir", "") == addon_dir:
			p["installed"] = installed
			return


func set_addon_branch(
	repo_name: String, addon_dir: String, branch: String, commit: String = ""
) -> void:
	for p in get_addons(repo_name):
		if p.get("addon_dir", "") == addon_dir:
			p["branch"] = branch
			p.erase("tag")
			if not commit.is_empty():
				p["commit"] = commit
			return


func set_addon_tag(repo_name: String, addon_dir: String, tag: String, commit: String = "") -> void:
	for p in get_addons(repo_name):
		if p.get("addon_dir", "") == addon_dir:
			p["tag"] = tag
			p.erase("branch")
			if not commit.is_empty():
				p["commit"] = commit
			return


func set_addon_commit_lock(repo_name: String, addon_dir: String, commit: String) -> void:
	for p in get_addons(repo_name):
		if p.get("addon_dir", "") == addon_dir:
			p.erase("branch")
			p.erase("tag")
			p["commit"] = commit
			return


func set_addon_commit(repo_name: String, addon_dir: String, commit: String) -> void:
	for p in get_addons(repo_name):
		if p.get("addon_dir", "") == addon_dir:
			p["commit"] = commit
			return


func update_addon_metadata(repo_name: String, addon_dir: String, metadata: Dictionary) -> void:
	for p in get_addons(repo_name):
		if p.get("addon_dir", "") == addon_dir:
			for key in ["name", "description", "version", "author", "type"]:
				if metadata.has(key):
					p[key] = metadata[key]
			return


func set_repo_locked(repo_name: String, locked: bool) -> void:
	var repo = get_repo(repo_name)
	if not repo.is_empty():
		if locked:
			repo["locked"] = true
		else:
			repo.erase("locked")


func is_repo_locked(repo_name: String) -> bool:
	return get_repo(repo_name).get("locked", false)


# ---------------------------------------------------------------------------
# Release-specific mutations
# ---------------------------------------------------------------------------


func set_addon_installed_from(repo_name: String, addon_dir: String, from: String) -> void:
	for p in get_addons(repo_name):
		if p.get("addon_dir", "") == addon_dir:
			p["installed_from"] = from
			return


func set_addon_installed_tag(repo_name: String, addon_dir: String, tag: String) -> void:
	for p in get_addons(repo_name):
		if p.get("addon_dir", "") == addon_dir:
			p["installed_tag"] = tag
			return


func set_addon_installed_asset(repo_name: String, addon_dir: String, filename: String) -> void:
	for p in get_addons(repo_name):
		if p.get("addon_dir", "") == addon_dir:
			if filename.is_empty():
				p.erase("installed_asset_filename")
			else:
				p["installed_asset_filename"] = filename
			return


func get_addon_installed_asset(repo_name: String, addon_dir: String) -> String:
	for p in get_addons(repo_name):
		if p.get("addon_dir", "") == addon_dir:
			return p.get("installed_asset_filename", "")
	return ""


func get_release_asset_pattern(repo_name: String) -> String:
	var repo = get_repo(repo_name)
	return repo.get("release_asset_pattern", "")


func get_repo_install_from(repo_name: String) -> String:
	var installed = get_installed_addons(repo_name)
	if installed.any(func(p): return p.get("installed_from", "") == "release"):
		return "release"
	return "source"


# ---------------------------------------------------------------------------
# Version mode helpers
# ---------------------------------------------------------------------------


## "branch" / "tag" / "commit" / "release" / "default"
static func get_version_mode(plugin: Dictionary) -> String:
	if plugin.get("installed_from", "") == "release":
		return "release"
	if plugin.has("tag") and not plugin.get("tag", "").is_empty():
		return "tag"
	if plugin.has("branch") and not plugin.get("branch", "").is_empty():
		return "branch"
	if plugin.has("commit") and not plugin.get("commit", "").is_empty():
		return "commit"
	return "default"


static func is_updatable(plugin: Dictionary) -> bool:
	var mode = get_version_mode(plugin)
	return mode == "branch" or mode == "default" or mode == "release"


## The ref string to pass to git checkout.
static func get_checkout_ref(plugin: Dictionary) -> String:
	var mode = get_version_mode(plugin)
	match mode:
		"tag":
			return plugin.get("tag", "")
		"branch":
			return plugin.get("branch", "")
		"commit":
			return plugin.get("commit", "")
	return ""


## Human-readable version label for UI.
static func get_version_label(plugin: Dictionary) -> String:
	var mode = get_version_mode(plugin)
	match mode:
		"release":
			return plugin.get("installed_tag", "")
		"tag":
			return plugin.get("tag", "")
		"branch":
			return plugin.get("branch", "")
		"commit":
			var c = plugin.get("commit", "")
			return c.left(7) if c.length() > 7 else c
	return ""


## Build a grouping of plugins by checkout ref for batch installation.
## Returns { ref_string: [plugin_dict, ...] }
## Release addons are grouped under "__release__".
static func group_addons_by_version(addons: Array) -> Dictionary:
	var groups: Dictionary = {}
	for p in addons:
		if p.get("installed_from", "") == "release":
			if not groups.has("__release__"):
				groups["__release__"] = []
			groups["__release__"].append(p)
			continue
		var ref = get_checkout_ref(p)
		if ref.is_empty():
			ref = "__default__"
		if not groups.has(ref):
			groups[ref] = []
		groups[ref].append(p)
	return groups


# ---------------------------------------------------------------------------
# Scan merge (after version change)
# ---------------------------------------------------------------------------


## Merge freshly scanned addon data into existing repo entry.
## Preserves user settings (installed, branch/tag/commit).
## Returns {added: [addon_dir], removed: [addon_dir]}
func merge_scan_results(repo_name: String, scanned_addons: Array) -> Dictionary:
	var repo = get_repo(repo_name)
	var existing_addons: Array = repo.get("addons", [])

	var existing_by_dir: Dictionary = {}
	for p in existing_addons:
		existing_by_dir[p.get("addon_dir", "")] = p

	var merged: Array = []
	var added: Array = []
	var removed: Array = []
	var scanned_dirs: Dictionary = {}

	for sp in scanned_addons:
		var dir: String = sp.get("addon_dir", sp.get("plugin_dir", ""))
		scanned_dirs[dir] = true
		if existing_by_dir.has(dir):
			var existing = existing_by_dir[dir]
			existing["name"] = sp.get("name", existing.get("name", ""))
			existing["description"] = sp.get("description", existing.get("description", ""))
			existing["version"] = sp.get("version", existing.get("version", ""))
			existing["author"] = sp.get("author", existing.get("author", ""))
			existing["type"] = _normalize_type(sp.get("type", existing.get("type", "")))
			merged.append(existing)
		else:
			var new_addon: Dictionary = {
				"name": sp.get("name", ""),
				"description": sp.get("description", ""),
				"type": _normalize_type(sp.get("type", "")),
				"addon_dir": dir,
				"version": sp.get("version", ""),
				"author": sp.get("author", ""),
				"installed": false,
			}
			merged.append(new_addon)
			added.append(dir)

	for dir in existing_by_dir:
		if not scanned_dirs.has(dir):
			removed.append(dir)

	repo["addons"] = merged
	set_repo(repo_name, repo)
	return {"added": added, "removed": removed}


# ---------------------------------------------------------------------------
# Conflict checking
# ---------------------------------------------------------------------------


## Check which addon_dirs conflict with existing addons directories on disk.
## Returns Array of addon_dir strings that have conflicts.
func check_dir_conflicts(addon_dirs: Array, existing_addon_names: PackedStringArray) -> Array:
	var conflicts: Array = []
	for dir in addon_dirs:
		var basename = dir.get_file() if "/" in dir else dir
		if basename in existing_addon_names:
			conflicts.append(dir)
	return conflicts


## Find which repo currently owns (has installed) the given addon_dir.
## Returns the repo_name, or "" if no repo owns it.
func find_owner_repo(addon_dir: String) -> String:
	for repo_name in get_repos():
		for p in get_addons(repo_name):
			if p.get("addon_dir", "") == addon_dir and p.get("installed", false):
				return repo_name
	return ""


# ---------------------------------------------------------------------------
# Consistency check
# ---------------------------------------------------------------------------


## Check filesystem vs addons.json consistency.
## Returns Array of {type, repo_name, addon_dir, message}.
func check_consistency() -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	var tracked_dirs: Dictionary = {}

	for repo_name in get_repos():
		var repo = get_repo(repo_name)
		var plug_dir = _GM.get_plugged_dir().path_join(repo_name)
		var is_release_repo = get_repo_install_from(repo_name) == "release"

		if not is_release_repo and not DirAccess.dir_exists_absolute(plug_dir):
			(
				issues
				. append(
					{
						"type": "missing_clone",
						"repo_name": repo_name,
						"addon_dir": "",
						"message":
						(
							TranslationServer.get_or_add_domain(_DOMAIN_NAME).translate(
								"CONSISTENCY_MISSING_CLONE"
							)
							% plug_dir
						),
					}
				)
			)

		for p in repo.get("addons", []):
			if not p.get("installed", false):
				continue
			var ipath = p.get("addon_dir", "")
			tracked_dirs[ipath] = true
			var full_path = "res://" + ipath
			var global_path = ProjectSettings.globalize_path(full_path)
			if not DirAccess.dir_exists_absolute(global_path):
				(
					issues
					. append(
						{
							"type": "missing_installed",
							"repo_name": repo_name,
							"addon_dir": p.get("addon_dir", ""),
							"message":
							(
								TranslationServer.get_or_add_domain(_DOMAIN_NAME).translate(
									"CONSISTENCY_MISSING_INSTALLED"
								)
								% full_path
							),
						}
					)
				)

	var addons_path = ProjectSettings.globalize_path("res://addons")
	if DirAccess.dir_exists_absolute(addons_path):
		var dir = DirAccess.open(addons_path)
		if dir:
			dir.list_dir_begin()
			var fname = dir.get_next()
			while not fname.is_empty():
				if dir.current_is_dir() and fname != "gd-plug-plus":
					var addon_dir = "addons/" + fname
					if not tracked_dirs.has(addon_dir):
						(
							issues
							. append(
								{
									"type": "untracked",
									"repo_name": "",
									"addon_dir": addon_dir,
									"message":
									(
										TranslationServer.get_or_add_domain(_DOMAIN_NAME).translate(
											"CONSISTENCY_UNTRACKED"
										)
										% addon_dir
									),
								}
							)
						)
				fname = dir.get_next()
			dir.list_dir_end()

	return issues


# ---------------------------------------------------------------------------
# Migration from legacy plug.gd + index.cfg
# ---------------------------------------------------------------------------


## Migrate from gd-plug's plug.gd + index.cfg to addons.json.
## plugged_plugins: gd_plug._plugged_plugins (from running _plugging())
## installed_plugins: from index.cfg [plugin] installed
func migrate_from_legacy(plugged_plugins: Dictionary, installed_plugins: Dictionary) -> void:
	for plugin_name in plugged_plugins:
		var pp = plugged_plugins[plugin_name]
		var ip = installed_plugins.get(plugin_name, {})
		var url: String = pp.get("url", "")
		var repo_name = _GM.repo_name_from_url(url) if not url.is_empty() else plugin_name

		if has_repo(repo_name):
			continue

		var plug_dir_path = _GM.get_plugged_dir().path_join(repo_name)
		var commit_hash = ""
		if DirAccess.dir_exists_absolute(plug_dir_path.path_join(".git")):
			var output: Array = []
			_GM.git(plug_dir_path, ["rev-parse", "HEAD"], output)
			if output.size() > 0:
				commit_hash = output[0].strip_edges()

		var scanned = _GM.scan_local_addons(plug_dir_path)

		var addons_arr: Array = []
		if scanned.size() > 0:
			for sp in scanned:
				var addon: Dictionary = {
					"name": sp.get("name", ""),
					"description": sp.get("description", ""),
					"type": _normalize_type(sp.get("type", "")),
					"addon_dir": sp.get("addon_dir", sp.get("plugin_dir", "")),
					"version": sp.get("version", ""),
					"author": sp.get("author", ""),
					"installed": plugin_name in installed_plugins,
				}
				var branch_val: String = pp.get("branch", "")
				if not branch_val.is_empty():
					addon["branch"] = branch_val
				var tag_val: String = pp.get("tag", "")
				if not tag_val.is_empty():
					addon["tag"] = tag_val
					addon.erase("branch")
				if not commit_hash.is_empty():
					addon["commit"] = commit_hash
				var commit_val: String = pp.get("commit", "")
				if not commit_val.is_empty():
					addon["commit"] = commit_val
					addon.erase("branch")
					addon.erase("tag")
				addons_arr.append(addon)
		else:
			var addon: Dictionary = {
				"name": plugin_name,
				"description": "",
				"type": "plugin",
				"addon_dir": "addons/" + plugin_name,
				"version": "",
				"author": "",
				"installed": plugin_name in installed_plugins,
			}
			var branch_val: String = pp.get("branch", "")
			if not branch_val.is_empty():
				addon["branch"] = branch_val
			var tag_val: String = pp.get("tag", "")
			if not tag_val.is_empty():
				addon["tag"] = tag_val
				addon.erase("branch")
			if not commit_hash.is_empty():
				addon["commit"] = commit_hash
			var commit_val: String = pp.get("commit", "")
			if not commit_val.is_empty():
				addon["commit"] = commit_val
				addon.erase("branch")
				addon.erase("tag")
			addons_arr.append(addon)

		var repo: Dictionary = {"url": url, "addons": addons_arr}

		var include_arr: Array = pp.get("include", [])
		if not include_arr.is_empty():
			repo["include_override"] = include_arr
		var exclude_arr: Array = pp.get("exclude", [])
		if not exclude_arr.is_empty():
			repo["exclude_override"] = exclude_arr
		if pp.get("dev", false):
			repo["dev"] = true

		set_repo(repo_name, repo)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


static func _normalize_type(raw_type: String) -> String:
	if raw_type.is_empty():
		return ""
	match raw_type:
		"editor_plugin":
			return "plugin"
		"gdextension":
			return "extension"
		"plugin", "extension":
			return raw_type
	if "extension" in raw_type.to_lower():
		return "extension"
	return "plugin"
