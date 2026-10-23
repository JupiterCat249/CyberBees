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


## ⚠️ 迭代146（人 2026-10-23 实测）：**绝不要实现 `_handles` / `_edit` / `_make_visible`**。
##   这三个是 **main-screen 插件**三件套：一旦实现，编辑器会把主工作区交给本插件，
##   表现为"UI 被破坏 / 资源打不开"（本轮实测踩到）。
##   ⇒ 本插件只做 Dock，资源由面板里的路径 + 加载按钮选择。
