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
	_win.transient = true
	## ⚠️ 迭代148（人 2026-10-23 实测）：**绝不要开 `wrap_controls`**。
	##   它与子节点的 SIZE_EXPAND_FILL 形成"内容撑大窗口 → 子节点再撑大"的回环，
	##   实测窗口高度远超屏幕。⇒ 固定尺寸 + 按屏幕可用区夹紧 + 手动居中。
	_win.wrap_controls = false
	_win.close_requested.connect(_close)
	_panel = PANEL.new()
	_panel.name = "FxPanel"
	_win.add_child(_panel)
	EditorInterface.get_base_control().add_child(_win)
	var avail := DisplayServer.screen_get_usable_rect()
	var w: int = mini(560, maxi(420, avail.size.x - 120))
	var h: int = mini(420, maxi(280, avail.size.y - 200))
	## 居中：以屏幕可用区为准（不用 popup_centered()，它会按内容最小尺寸重算）
	var pos := avail.position + Vector2i((avail.size.x - w) / 2, (avail.size.y - h) / 2)
	_win.size = Vector2i(w, h)
	_win.position = pos
	_win.popup()


func _close() -> void:
	if _win != null and is_instance_valid(_win):
		_win.queue_free()
	_win = null
	_panel = null
