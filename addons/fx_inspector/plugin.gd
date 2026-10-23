@tool
extends EditorPlugin
## Fx Inspector —— **视觉特效参数预览面板**（人 2026-10-23 意见B · 选"EditorPlugin 面板"）
##
## 目的：把 FxParams 的数值改动**在编辑器里立刻看到**（不用跑游戏），
##   并为将来同类"参数资源 + 预览面板"功能提供**可复用的骨架**：
##     ① dock 里选资源（Inspector 选中优先）② 用真实场景渲染样例 ③ 参数变更即时刷新。

const DOCK := preload("res://addons/fx_inspector/fx_dock.gd")

var _dock: Control = null


func _enter_tree() -> void:
	_dock = DOCK.new()
	_dock.name = "Fx Inspector"
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _dock)


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null


## 在编辑器里选中资源时，把 FxParams 自动送进面板（"所见即所改"）
func _handles(object: Object) -> bool:
	return object is Resource and object.get_script() != null \
		and String(object.get_script().resource_path).ends_with("fx_params.gd")


func _edit(object: Object) -> void:
	if _dock != null and object != null:
		_dock.set_params(object)
