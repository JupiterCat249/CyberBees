@tool
extends EditorPlugin
## Fx Inspector —— **视觉特效参数预览**（人 2026-10-23 意见B）
##
## ⚠️ 形态决定（迭代147，人两次实测反馈后）：**不注册 Dock**。
##   理由：Dock 插槽会与编辑器底部/右侧面板争布局 —— 实测"启用即破坏底部 UI 栏"。
##   ⇒ 改为 **Project ▸ Tools 菜单项 + 独立窗口**：窗口是浮层，不参与编辑器布局，关掉即净。
##
## ⚠️ 同时**绝不实现** `_handles` / `_edit` / `_make_visible`（main-screen 三件套会接管主工作区）。
##   这两条都有读数闸守着：tests/test_editor_plugin_safety.gd。

const PANEL := preload("res://addons/fx_inspector/fx_panel.gd")

var _win: Window = null
var _panel: Control = null


func _enter_tree() -> void:
	add_tool_menu_item("Fx 参数预览…", _open)


func _exit_tree() -> void:
	remove_tool_menu_item("Fx 参数预览…")
	_close()


func _open() -> void:
	if _win != null and is_instance_valid(_win):
		_win.popup_centered()
		return
	_win = Window.new()
	_win.title = "Fx 参数预览（FxParams）"
	_win.size = Vector2i(560, 420)
	_win.transient = true
	_win.wrap_controls = true
	_win.close_requested.connect(_close)
	_panel = PANEL.new()
	_panel.name = "FxPanel"
	_win.add_child(_panel)
	EditorInterface.get_base_control().add_child(_win)
	_win.popup_centered()


func _close() -> void:
	if _win != null and is_instance_valid(_win):
		_win.queue_free()
	_win = null
	_panel = null
