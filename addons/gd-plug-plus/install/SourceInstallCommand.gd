@tool
class_name SourceInstallCommand
extends InstallCommand

## Wraps the existing git clone / fetch / checkout / copy flow.
## Executes within a WorkerThreadPool task (same as existing pattern).

var _plug_dir: String
var _project_root: String


func _init(repo_name: String, addon_info: Dictionary, plug_dir: String, project_root: String):
	super(repo_name, addon_info)
	_plug_dir = plug_dir
	_project_root = project_root


func execute() -> void:
	if _cancelled:
		completed.emit(false, "Cancelled")
		return
	var pdir: String = _addon_info.get("addon_dir", "")
	if pdir.is_empty():
		completed.emit(false, "No addon_dir")
		return
	progress_updated.emit("Copying %s..." % pdir)
	GitManager.copy_addon_dir(_plug_dir, pdir, _project_root)
	completed.emit(true, "")
