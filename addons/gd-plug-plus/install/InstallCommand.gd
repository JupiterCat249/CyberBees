@tool
class_name InstallCommand
extends RefCounted

## Command base — abstracts "install" into a schedulable, cancellable object.
## Eliminates "if installed_from == release" branches in AddonManager.

signal completed(success: bool, error: String)
signal progress_updated(message: String)

var _repo_name: String
var _addon_info: Dictionary
var _cancelled: bool = false


func _init(repo_name: String, addon_info: Dictionary):
	_repo_name = repo_name
	_addon_info = addon_info


func execute() -> void:
	pass


func cancel() -> void:
	_cancelled = true
