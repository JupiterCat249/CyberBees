class_name GitManager
extends RefCounted

## Reusable Git utility class.
## All methods are static — no instance needed.
## Platform-aware (Windows cmd / Unix bash).

const ERR_CANCELLED = -99
const GIT_TIMEOUT_ARGS: Array = ["-c", "http.lowSpeedLimit=100", "-c", "http.lowSpeedTime=60"]
const _ProxyConfig = preload("res://addons/gd-plug-plus/release/ProxyConfig.gd")
const _DOMAIN_NAME = "gd-plug-plus"

static var _cancel_requested: bool = false
static var _active_pid: int = -1
static var _cancel_semaphore: Semaphore = null
static var last_error: String = ""


static func get_plugged_dir() -> String:
	var base = OS.get_temp_dir().path_join("gd-plug-plus").path_join("repos")
	if not DirAccess.dir_exists_absolute(base):
		DirAccess.make_dir_recursive_absolute(base)
	return base


static func _tr(key: String) -> String:
	return TranslationServer.get_or_add_domain(_DOMAIN_NAME).translate(key)


static func request_cancel():
	_cancel_requested = true
	if _active_pid > 0:
		_kill_process_tree(_active_pid)
		_active_pid = -1
	if _cancel_semaphore != null:
		_cancel_semaphore.post()


static func reset_cancel():
	_cancel_requested = false
	_cancel_semaphore = null
	last_error = ""


## Call git directly, bypassing cmd.exe to avoid % expansion issues on Windows.
static func git(repo_dir: String, args: Array, output: Array = []) -> int:
	var full_args: Array = []
	full_args.append_array(_ProxyConfig.get_git_proxy_args())
	full_args.append_array(["-C", repo_dir])
	full_args.append_array(args)
	return OS.execute("git", full_args, output)


# ---------------------------------------------------------------------------
# Cancellable process execution
# ---------------------------------------------------------------------------


## Run git with cancel support. Uses Thread + Semaphore (wait/notify) so the
## calling thread blocks without polling. On cancel, request_cancel() kills the
## process and posts the semaphore to wake the caller immediately.
## Returns {"exit": int, "output": String}.
static func _execute_cancellable(args: Array, read_stderr: bool = true) -> Dictionary:
	var result := {"exit": FAILED, "output": ""}

	if _cancel_requested:
		result["exit"] = ERR_CANCELLED
		return result

	var proxy_args := _ProxyConfig.get_git_proxy_args()
	if not proxy_args.is_empty():
		var combined := Array()
		combined.append_array(proxy_args)
		combined.append_array(args)
		args = combined

	var cache_dir = OS.get_cache_dir()
	var tmp_out = cache_dir.path_join("gd-plug-git-out.tmp")
	var tmp_rc = cache_dir.path_join("gd-plug-git-rc.tmp")

	_cleanup_tmp_files([tmp_out, tmp_rc])

	var redirect = (
		"2>&1" if read_stderr else ("2>nul" if OS.get_name() == "Windows" else "2>/dev/null")
	)

	match OS.get_name():
		"Windows":
			var tmp_bat = cache_dir.path_join("gd-plug-git-run.bat")
			var git_line = "git"
			for a in args:
				git_line += ' "' + a.replace('"', '""') + '"'
			var bat_out = tmp_out.replace("/", "\\")
			var bat_rc = tmp_rc.replace("/", "\\")
			var script = (
				'@echo off\r\n%s %s > "%s"\r\necho %%ERRORLEVEL%% > "%s"\r\n'
				% [git_line, redirect, bat_out, bat_rc]
			)
			var f = FileAccess.open(tmp_bat, FileAccess.WRITE)
			if f == null:
				return result
			f.store_string(script)
			f.close()
			_active_pid = OS.create_process("cmd", ["/C", tmp_bat.replace("/", "\\")])
		_:
			var git_line = "git"
			for a in args:
				git_line += " '" + a.replace("'", "'\\''") + "'"
			var cmd = '%s %s > "%s"; echo $? > "%s"' % [git_line, redirect, tmp_out, tmp_rc]
			_active_pid = OS.create_process("bash", ["-c", cmd])

	if _active_pid <= 0:
		return result

	# Wait/notify: monitor thread watches process, posts semaphore on completion.
	# request_cancel() also posts semaphore + kills process for immediate wakeup.
	_cancel_semaphore = Semaphore.new()
	var monitor = Thread.new()
	monitor.start(_monitor_process.bind(_active_pid, _cancel_semaphore))

	_cancel_semaphore.wait()

	monitor.wait_to_finish()
	_cancel_semaphore = null

	if _cancel_requested:
		_active_pid = -1
		_cleanup_tmp_files([tmp_out, tmp_rc])
		result["exit"] = ERR_CANCELLED
		return result

	_active_pid = -1

	if FileAccess.file_exists(tmp_out):
		var f = FileAccess.open(tmp_out, FileAccess.READ)
		if f:
			result["output"] = f.get_as_text()

	if FileAccess.file_exists(tmp_rc):
		var f = FileAccess.open(tmp_rc, FileAccess.READ)
		if f:
			result["exit"] = f.get_as_text().strip_edges().to_int()

	_cleanup_tmp_files([tmp_out, tmp_rc])
	return result


## Monitor thread: waits for process to exit, then signals the semaphore.
## Uses OS.is_process_running which is a lightweight kernel query, not busy-wait.
static func _monitor_process(pid: int, sem: Semaphore):
	while pid > 0 and OS.is_process_running(pid):
		OS.delay_msec(50)
	sem.post()


static func _kill_process_tree(pid: int):
	match OS.get_name():
		"Windows":
			OS.create_process("cmd", ["/C", "taskkill /F /T /PID %d 2>nul" % pid])
		_:
			OS.create_process(
				"bash", ["-c", "pkill -9 -P %d 2>/dev/null; kill -9 %d 2>/dev/null" % [pid, pid]]
			)


static func _cleanup_tmp_files(paths: Array):
	for p in paths:
		if p is String and FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	var bat = OS.get_cache_dir().path_join("gd-plug-git-run.bat")
	if FileAccess.file_exists(bat):
		DirAccess.remove_absolute(bat)


# ---------------------------------------------------------------------------
# Remote queries (no clone needed)
# ---------------------------------------------------------------------------


## Returns {default_branch, branches, tags, ref_commits}.
## On cancel: includes "cancelled": true. On error: includes "error": String.
static func ls_remote(url: String) -> Dictionary:
	var result := {
		"default_branch": "",
		"branches": PackedStringArray(),
		"tags": PackedStringArray(),
	}

	PlugLogger.info(_tr("LOG_REMOTE_QUERY") % url)

	var args: Array = []
	args.append_array(GIT_TIMEOUT_ARGS)
	args.append_array(["ls-remote", "--symref", url, "HEAD"])
	PlugLogger.debug("ls-remote: git ls-remote --symref HEAD ...")
	var r = _execute_cancellable(args)
	PlugLogger.debug("ls-remote: HEAD query exit=%d" % r["exit"])

	if r["exit"] == ERR_CANCELLED:
		result["cancelled"] = true
		return result
	if r["exit"] != 0:
		result["error"] = _parse_git_error(r["output"].strip_edges(), r["exit"])
		PlugLogger.info(_tr("LOG_REMOTE_FAILED") % result["error"])
		return result

	for line in r["output"].split("\n"):
		line = line.strip_edges()
		if line.begins_with("ref: refs/heads/"):
			var parts = line.split("\t")
			if parts.size() >= 1:
				result["default_branch"] = parts[0].replace("ref: refs/heads/", "")
			break

	if result["default_branch"].is_empty():
		result["default_branch"] = "main"

	if _cancel_requested:
		result["cancelled"] = true
		return result

	args.clear()
	args.append_array(GIT_TIMEOUT_ARGS)
	args.append_array(["ls-remote", "--heads", "--tags", url])
	PlugLogger.debug("ls-remote: git ls-remote --heads --tags ...")
	var r2 = _execute_cancellable(args)
	PlugLogger.debug("ls-remote: heads+tags query exit=%d" % r2["exit"])

	if r2["exit"] == ERR_CANCELLED:
		result["cancelled"] = true
		return result

	if r2["exit"] == 0 and not r2["output"].is_empty():
		var branches: PackedStringArray = []
		var tags: PackedStringArray = []
		var ref_commits: Dictionary = {}
		var tag_deref: Dictionary = {}
		for line in r2["output"].split("\n"):
			line = line.strip_edges()
			if line.is_empty():
				continue
			var parts = line.split("\t")
			if parts.size() < 2:
				continue
			var hash_short = parts[0].left(7)
			var ref = parts[1]
			if ref.begins_with("refs/heads/"):
				var bname = ref.replace("refs/heads/", "")
				branches.append(bname)
				ref_commits[bname] = hash_short
			elif ref.ends_with("^{}"):
				var tname = ref.replace("refs/tags/", "").replace("^{}", "")
				tag_deref[tname] = hash_short
			elif ref.begins_with("refs/tags/"):
				var tname = ref.replace("refs/tags/", "")
				tags.append(tname)
				ref_commits[tname] = hash_short
		for tname in tag_deref:
			ref_commits[tname] = tag_deref[tname]
		result["branches"] = branches
		result["tags"] = tags
		result["ref_commits"] = ref_commits

	PlugLogger.debug(
		(
			"ls-remote: default_branch=%s, %d branches, %d tags"
			% [result["default_branch"], result["branches"].size(), result["tags"].size()]
		)
	)
	return result


# ---------------------------------------------------------------------------
# Local repo queries (need a cloned repo)
# ---------------------------------------------------------------------------


## Get branches, tags and ref_commits from local repo (no network).
## Returns same structure as ls_remote: {default_branch, branches, tags, ref_commits}
static func get_local_refs(repo_dir: String) -> Dictionary:
	var result := {
		"default_branch": "",
		"branches": PackedStringArray(),
		"tags": PackedStringArray(),
		"ref_commits": {},
	}
	if not DirAccess.dir_exists_absolute(repo_dir + "/.git"):
		return result

	var output: Array = []

	git(repo_dir, ["symbolic-ref", "refs/remotes/origin/HEAD"], output)
	if output.size() > 0:
		var ref = output[0].strip_edges()
		if ref.begins_with("refs/remotes/origin/"):
			result["default_branch"] = ref.replace("refs/remotes/origin/", "")
	output.clear()

	if result["default_branch"].is_empty():
		git(repo_dir, ["rev-parse", "--abbrev-ref", "HEAD"], output)
		if output.size() > 0:
			var b = output[0].strip_edges()
			if b != "HEAD":
				result["default_branch"] = b
		output.clear()
	if result["default_branch"].is_empty():
		result["default_branch"] = "main"

	var branches: PackedStringArray = []
	var ref_commits: Dictionary = {}
	git(
		repo_dir,
		["for-each-ref", "--format=%(objectname:short)\t%(refname:short)", "refs/remotes/origin/"],
		output
	)
	if output.size() > 0:
		for line in output[0].split("\n"):
			line = line.strip_edges()
			if line.is_empty():
				continue
			var parts = line.split("\t")
			if parts.size() < 2:
				continue
			var bname = parts[1].replace("origin/", "")
			if bname == "HEAD":
				continue
			branches.append(bname)
			ref_commits[bname] = parts[0]
	output.clear()

	var tags: PackedStringArray = []
	git(
		repo_dir,
		[
			"for-each-ref",
			"--format=%(objectname:short)\t%(refname:short)",
			"--sort=-creatordate",
			"refs/tags/"
		],
		output
	)
	if output.size() > 0:
		for line in output[0].split("\n"):
			line = line.strip_edges()
			if line.is_empty():
				continue
			var parts = line.split("\t")
			if parts.size() < 2:
				continue
			tags.append(parts[1])
			ref_commits[parts[1]] = parts[0]
	output.clear()

	result["branches"] = branches
	result["tags"] = tags
	result["ref_commits"] = ref_commits
	PlugLogger.debug(
		(
			"get_local_refs: default=%s, %d branches, %d tags"
			% [result["default_branch"], branches.size(), tags.size()]
		)
	)
	return result


## Returns {branch, commit_short, commit_full, tag, date}
static func get_current_info(repo_dir: String) -> Dictionary:
	var info := {
		"branch": "",
		"commit_short": "",
		"commit_full": "",
		"tag": "",
		"date": "",
	}
	if not DirAccess.dir_exists_absolute(repo_dir + "/.git"):
		return info

	var output: Array = []

	git(repo_dir, ["rev-parse", "--abbrev-ref", "HEAD"], output)
	if output.size() > 0:
		var b = output[0].strip_edges()
		info["branch"] = b if b != "HEAD" else ""
	output.clear()

	git(repo_dir, ["rev-parse", "--short", "HEAD"], output)
	if output.size() > 0:
		info["commit_short"] = output[0].strip_edges()
	output.clear()

	git(repo_dir, ["rev-parse", "HEAD"], output)
	if output.size() > 0:
		info["commit_full"] = output[0].strip_edges()
	output.clear()

	git(repo_dir, ["describe", "--tags", "--exact-match"], output)
	if output.size() > 0:
		info["tag"] = output[0].strip_edges()
	output.clear()

	git(repo_dir, ["log", "-1", "--format=%ai"], output)
	if output.size() > 0:
		info["date"] = _format_date(output[0].strip_edges())
	output.clear()

	return info


## Returns [{hash, hash_short, message, date}, ...]
static func get_commit_log(
	repo_dir: String, ref: String = "HEAD", count: int = 50
) -> Array[Dictionary]:
	var commits: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(repo_dir + "/.git"):
		return commits

	var output: Array = []
	var args: Array = ["log", ref, "--format=%H%x09%h%x09%s%x09%ai", "-n", str(count)]
	git(repo_dir, args, output)
	if output.size() > 0:
		for line in output[0].split("\n"):
			line = line.strip_edges()
			if line.is_empty():
				continue
			var parts = line.split("\t")
			if parts.size() < 4:
				continue
			(
				commits
				. append(
					{
						"hash": parts[0],
						"hash_short": parts[1],
						"message": parts[2],
						"date": _format_date(parts[3]),
					}
				)
			)
	return commits


static func get_remote_default_branch(repo_dir: String) -> String:
	if not DirAccess.dir_exists_absolute(repo_dir + "/.git"):
		return "main"
	var output: Array = []
	git(repo_dir, ["symbolic-ref", "refs/remotes/origin/HEAD"], output)
	if output.size() > 0:
		var ref = output[0].strip_edges()
		if ref.begins_with("refs/remotes/origin/"):
			return ref.replace("refs/remotes/origin/", "")
	output.clear()
	git(repo_dir, ["remote", "show", "origin"], output)
	if output.size() > 0:
		for line in output[0].split("\n"):
			line = line.strip_edges()
			if line.begins_with("HEAD branch:"):
				return line.replace("HEAD branch:", "").strip_edges()
	return "main"


## Local-only compare HEAD vs origin/<branch> without fetching.
static func local_behind_count(repo_dir: String, branch: String = "") -> int:
	if not DirAccess.dir_exists_absolute(repo_dir + "/.git"):
		return 0
	var output: Array = []
	if branch.is_empty():
		git(repo_dir, ["symbolic-ref", "refs/remotes/origin/HEAD"], output)
		if output.size() > 0:
			var ref = output[0].strip_edges()
			if ref.begins_with("refs/remotes/origin/"):
				branch = ref.replace("refs/remotes/origin/", "")
		output.clear()
		if branch.is_empty():
			branch = "main"
	git(repo_dir, ["rev-list", "--count", "HEAD..origin/%s" % branch], output)
	if output.size() > 0:
		return output[0].strip_edges().to_int()
	return 0


## Fetch remote and compare. Returns {ahead: int, behind: int}
static func fetch_and_compare(repo_dir: String, branch: String = "") -> Dictionary:
	var result := {"ahead": 0, "behind": 0}
	if not DirAccess.dir_exists_absolute(repo_dir + "/.git"):
		return result

	var output: Array = []

	if branch.is_empty():
		git(repo_dir, ["symbolic-ref", "refs/remotes/origin/HEAD"], output)
		if output.size() > 0:
			var ref = output[0].strip_edges()
			if ref.begins_with("refs/remotes/origin/"):
				branch = ref.replace("refs/remotes/origin/", "")
		output.clear()
		if branch.is_empty():
			branch = "main"

	git(repo_dir, ["fetch", "origin", branch], output)
	output.clear()

	git(repo_dir, ["rev-list", "--count", "--left-right", "HEAD...origin/%s" % branch], output)
	if output.size() > 0:
		var parts = output[0].strip_edges().split("\t")
		if parts.size() == 2:
			result["ahead"] = parts[0].to_int()
			result["behind"] = parts[1].to_int()
	return result


# ---------------------------------------------------------------------------
# Clone / checkout / fetch operations
# ---------------------------------------------------------------------------


static func shallow_clone(url: String, dest: String, branch: String = "") -> int:
	last_error = ""
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	PlugLogger.info(_tr("LOG_CLONE_START") % url)
	var args: Array = []
	args.append_array(GIT_TIMEOUT_ARGS)
	if branch.is_empty():
		args.append_array(["clone", "--depth=1", url, dest])
	else:
		args.append_array(["clone", "--depth=1", "--single-branch", "--branch", branch, url, dest])
	var r = _execute_cancellable(args)
	if r["exit"] == ERR_CANCELLED:
		PlugLogger.debug("clone: cancelled")
		return ERR_CANCELLED
	if r["exit"] == OK:
		PlugLogger.info(_tr("LOG_CLONE_SUCCESS"))
	else:
		var raw_err = r["output"].strip_edges()
		last_error = _parse_git_error(raw_err, r["exit"])
		PlugLogger.info(_tr("LOG_CLONE_FAILED") % last_error)
		if not raw_err.is_empty():
			PlugLogger.debug("clone: raw output: %s" % raw_err)
	return r["exit"]


static func checkout(repo_dir: String, ref: String) -> int:
	var output: Array = []
	return git(repo_dir, ["checkout", ref], output)


static func fetch_ref(repo_dir: String, ref: String) -> int:
	var output: Array = []
	return git(repo_dir, ["fetch", "origin", ref, "--depth=1"], output)


static func pull_current(repo_dir: String) -> int:
	var output: Array = []
	return git(repo_dir, ["pull", "--rebase"], output)


static func rev_parse_head(repo_dir: String) -> String:
	var output: Array = []
	if git(repo_dir, ["rev-parse", "HEAD"], output) == OK and output.size() > 0:
		return output[0].strip_edges()
	return ""


## Copy an addon directory from staging to project.
## source_base: global path to .plugged/repo_name
## addon_dir: relative path like "addons/my_addon"
## dest_base: global path to project root (res://)
## Returns file count copied.
static func copy_addon_dir(source_base: String, addon_dir: String, dest_base: String) -> int:
	var from = source_base + "/" + addon_dir
	var to = dest_base + "/" + addon_dir
	if not DirAccess.dir_exists_absolute(from):
		return 0
	return _copy_dir_recursive(from, to)


static func _copy_dir_recursive(from: String, to: String) -> int:
	var dir = DirAccess.open(from)
	if dir == null:
		return 0
	DirAccess.make_dir_recursive_absolute(to)
	dir.include_hidden = true
	dir.list_dir_begin()
	var fname = dir.get_next()
	var count := 0
	while not fname.is_empty():
		var src = from + "/" + fname
		var dst = to + "/" + fname
		if dir.current_is_dir():
			if fname != ".git" and fname != ".godot":
				count += _copy_dir_recursive(src, dst)
		else:
			dir.copy(src, dst)
			count += 1
		fname = dir.get_next()
	dir.list_dir_end()
	return count


## Delete an installed plugin directory from the project.
## Safety: refuses to delete project root or anything outside addons/.
static func delete_installed_dir(addon_dir_relative: String) -> void:
	if addon_dir_relative.strip_edges().is_empty():
		PlugLogger.debug("delete_installed_dir: refused — addon_dir is empty")
		return
	if not addon_dir_relative.begins_with("addons/"):
		PlugLogger.debug(
			"delete_installed_dir: refused — not under addons/: %s"
			% addon_dir_relative
		)
		return
	var full = ProjectSettings.globalize_path("res://" + addon_dir_relative)
	if DirAccess.dir_exists_absolute(full):
		delete_directory(full)


static func delete_directory(path: String) -> void:
	var clean := path.strip_edges()
	if clean.is_empty():
		PlugLogger.debug("delete_directory: refused — empty path")
		return
	var project_root := ProjectSettings.globalize_path("res://")
	if _is_path_equal_or_parent(clean, project_root):
		PlugLogger.debug(
			"delete_directory: REFUSED — would delete project root "
			+ "or ancestor: %s" % clean
		)
		return
	var home := OS.get_environment("HOME")
	if home.is_empty():
		home = OS.get_environment("USERPROFILE")
	if not home.is_empty() and _is_path_equal_or_parent(clean, home):
		PlugLogger.debug(
			"delete_directory: REFUSED — would delete home dir "
			+ "or ancestor: %s" % clean
		)
		return
	PlugLogger.debug("delete_directory: %s" % clean)
	match OS.get_name():
		"Windows":
			var win_path = clean.replace("/", "\\")
			OS.execute(
				"cmd", ["/C", 'rd /s /q "%s" 2>nul' % win_path]
			)
		_:
			OS.execute("bash", ["-c", "rm -rf '%s'" % clean])
	PlugLogger.debug("delete_directory done: %s" % clean)


static func _is_path_equal_or_parent(
	candidate: String, protected: String
) -> bool:
	var c := candidate.replace("\\", "/").trim_suffix("/")
	var p := protected.replace("\\", "/").trim_suffix("/")
	if c.is_empty() or p.is_empty():
		return false
	return p == c or p.begins_with(c + "/")


# ---------------------------------------------------------------------------
# Addon scanning
# ---------------------------------------------------------------------------


## Scan all Godot plugins and GDExtensions in a checked-out repo directory.
## Reuses scan_local_addons which mirrors Godot engine's own scanning logic.
## Returns {addons: Array[Dictionary], warnings: Array[String]}
static func scan_addons_in_dir(repo_dir: String) -> Dictionary:
	var result := {"addons": [] as Array[Dictionary], "warnings": [] as Array[String]}

	PlugLogger.info(_tr("LOG_SCAN_START"))
	var addons = scan_local_addons(repo_dir)

	if addons.is_empty():
		result["warnings"].append(_tr("WARN_NO_CFG_FOUND"))
		PlugLogger.info(_tr("LOG_SCAN_NOT_FOUND"))
	else:
		result["addons"] = addons
		PlugLogger.info(_tr("LOG_SCAN_FOUND") % addons.size())

	return result


static func _classify_structure(cfg_path: String) -> String:
	var dir = cfg_path.get_base_dir()
	if dir.is_empty():
		return "root_level"
	if dir.begins_with("addons/"):
		return "standard"
	if "addons/" in dir:
		return "deep_nested"
	return "no_addons"


## Scan a directory for Godot plugins and GDExtensions.
## Skip logic matches Godot engine's EditorFileSystem / EditorPluginSettings:
##   - directories starting with "." (covers .git, .godot, etc.)
##   - directories containing .gdignore
##   - directories containing project.godot (nested projects)
## Accepts either res:// or absolute path.
static func scan_local_addons(plug_dir: String) -> Array[Dictionary]:
	var addons: Array[Dictionary] = []
	var global_dir = plug_dir
	if plug_dir.begins_with("res://"):
		global_dir = ProjectSettings.globalize_path(plug_dir)
	if not DirAccess.dir_exists_absolute(global_dir):
		return addons

	_scan_dir_for_addons(global_dir, global_dir, addons)
	return addons


static func _should_skip_directory(dir_path: String, dir_name: String) -> bool:
	if dir_name.begins_with("."):
		return true
	if FileAccess.file_exists(dir_path + "/.gdignore"):
		return true
	if FileAccess.file_exists(dir_path + "/project.godot"):
		return true
	return false


static func _scan_dir_for_addons(
	base_dir: String, current_dir: String, results: Array[Dictionary]
) -> void:
	var dir = DirAccess.open(current_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while not file_name.is_empty():
		if file_name.begins_with("."):
			file_name = dir.get_next()
			continue
		var full_path = current_dir + "/" + file_name
		if dir.current_is_dir():
			if not _should_skip_directory(full_path, file_name):
				_scan_dir_for_addons(base_dir, full_path, results)
		elif file_name == "plugin.cfg":
			var cfg = ConfigFile.new()
			if cfg.load(full_path) == OK:
				var rel_dir = current_dir.replace(base_dir, "").trim_prefix("/")
				var cfg_rel = rel_dir + "/" + file_name if not rel_dir.is_empty() else file_name
				var script_file: String = cfg.get_value("plugin", "script", "")
				var language := "gdscript"
				if script_file.get_extension() == "cs":
					language = "csharp"
				(
					results
					. append(
						{
							"name": cfg.get_value("plugin", "name", rel_dir.get_file()),
							"description": cfg.get_value("plugin", "description", ""),
							"author": cfg.get_value("plugin", "author", ""),
							"version": cfg.get_value("plugin", "version", ""),
							"script": script_file,
							"type": "editor_plugin",
							"language": language,
							"cfg_path": cfg_rel,
							"addon_dir": rel_dir if not rel_dir.is_empty() else ".",
							"structure": _classify_structure(cfg_rel),
						}
					)
				)
		elif file_name.get_extension() == "gdextension":
			var rel_dir = current_dir.replace(base_dir, "").trim_prefix("/")
			var ext_rel = rel_dir + "/" + file_name if not rel_dir.is_empty() else file_name
			(
				results
				. append(
					{
						"name": file_name.get_basename(),
						"description": "GDExtension",
						"author": "",
						"version": "",
						"script": "",
						"type": "gdextension",
						"cfg_path": ext_rel,
						"addon_dir": rel_dir if not rel_dir.is_empty() else ".",
						"structure": _classify_structure(ext_rel),
					}
				)
			)
		file_name = dir.get_next()
	dir.list_dir_end()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


static func repo_name_from_url(repo: String) -> String:
	var s = repo.strip_edges().trim_suffix("/")
	if ":" in s and not "://" in s:
		# git@github.com:user/repo.git -> user/repo.git
		s = s.get_slice(":", 1)
	s = s.trim_suffix(".git")
	var parts = s.split("/")
	if parts.size() >= 2:
		return parts[-2] + "/" + parts[-1]
	return s


static func _format_date(raw: String) -> String:
	raw = raw.strip_edges().replace('"', "")
	if raw.length() >= 19:
		return raw.left(19).replace("T", " ")
	return raw


static func _parse_git_error(raw: String, exit_code: int) -> String:
	if raw.is_empty():
		return _tr("ERR_CLONE_FAILED") % exit_code
	var lower = raw.to_lower()
	if "timed out" in lower or "timeout" in lower:
		return _tr("ERR_TIMEOUT").replace("{SEP}", ",")
	if "not found" in lower or "404" in lower:
		return _tr("ERR_NOT_FOUND").replace("{SEP}", ",")
	if "could not resolve host" in lower:
		return _tr("ERR_DNS").replace("{SEP}", ",")
	if "authentication failed" in lower or "403" in lower:
		return _tr("ERR_AUTH").replace("{SEP}", ",")
	if "could not read from remote" in lower:
		return _tr("ERR_REMOTE_READ").replace("{SEP}", ",")
	if "connection refused" in lower:
		return _tr("ERR_REFUSED").replace("{SEP}", ",")
	if "ssl" in lower:
		return _tr("ERR_SSL").replace("{SEP}", ",")
	var fatal_idx = raw.find("fatal:")
	if fatal_idx >= 0:
		var msg = raw.substr(fatal_idx + 6).strip_edges()
		var newline = msg.find("\n")
		if newline >= 0:
			msg = msg.left(newline)
		return msg
	return _tr("ERR_CLONE_FAILED") % exit_code
