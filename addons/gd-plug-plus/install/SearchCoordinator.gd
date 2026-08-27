@tool
class_name SearchCoordinator
extends RefCounted

## Observer — coordinates parallel source + release search using signals.
## Replaces boolean flag polling in _process.

signal all_completed(source_result: Dictionary, release_result: Array)

var _source_done: bool = false
var _release_done: bool = false
var _release_active: bool = false
var _source_result: Dictionary = {}
var _release_result: Array = []


func reset(with_release: bool) -> void:
	_source_done = false
	_release_done = not with_release
	_release_active = with_release
	_source_result = {}
	_release_result = []


func is_release_active() -> bool:
	return _release_active


func on_source_completed(result: Dictionary) -> void:
	_source_result = result
	_source_done = true
	_try_complete()


func on_release_completed(result: Array) -> void:
	_release_result = result
	_release_done = true
	_try_complete()


func _try_complete() -> void:
	if _source_done and _release_done:
		all_completed.emit(_source_result, _release_result)
