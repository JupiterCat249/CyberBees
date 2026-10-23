extends GutTest
## **编辑器插件安全闸**（迭代147 · 人 2026-10-23 两次实测反馈）
##
## 背景：
##   ① `EditorPlugin._handles/_edit/_make_visible` 是 **main-screen 插件三件套** —— 一旦实现，
##      编辑器把主工作区交给插件 ⇒ 表现为"UI 被破坏 / 资源打不开"；
##   ② `add_control_to_dock()` 会与编辑器既有面板争布局 ⇒ 实测"启用即破坏底部 UI 栏"。
## ⇒ 本闸把两条都钉死：插件只允许「工具菜单 + 独立窗口」形态。

const PLUGIN := "res://addons/fx_inspector/plugin.gd"


func _read(p: String) -> String:
	var f := FileAccess.open(p, FileAccess.READ)
	assert_not_null(f, "应能读取：%s" % p)
	var s := f.get_as_text()
	f.close()
	return s


func _strip_comments(s: String) -> String:
	var out: Array = []
	for ln in s.split("\n"):
		if ln.strip_edges().begins_with("#"):
			continue
		out.append(ln)
	return "\n".join(out)


func test_plugin_has_no_main_screen_hooks() -> void:
	var code := _strip_comments(_read(PLUGIN))
	for bad in ["func _handles", "func _edit", "func _make_visible"]:
		assert_false(code.contains(bad), "插件不得实现 main-screen 三件套：%s" % bad)


func test_plugin_does_not_register_dock() -> void:
	var code := _strip_comments(_read(PLUGIN))
	assert_false(code.contains("add_control_to_dock"), "插件不得注入 Dock（会争编辑器面板布局）")
	assert_false(code.contains("DOCK_SLOT_"), "插件不得引用 Dock 插槽常量")


func test_plugin_uses_tool_menu_window() -> void:
	var code := _strip_comments(_read(PLUGIN))
	assert_true(code.contains("add_tool_menu_item"), "预览入口应走 Project ▸ Tools 菜单")
	assert_true(code.contains("Window.new()"), "预览面板应是独立窗口（不参与编辑器布局）")


func test_window_size_is_clamped_and_not_wrapping() -> void:
	## 迭代148（人 2026-10-23 实测）：`wrap_controls` 与子节点 EXPAND_FILL 会形成"内容撑窗口"回环
	##   ⇒ 窗口高度远超屏幕。要求：显式关闭 wrap_controls，并按屏幕可用区夹紧尺寸。
	var code := _strip_comments(_read(PLUGIN))
	assert_false(code.contains("wrap_controls = true"), "不得开启 wrap_controls（会回环撑高窗口）")
	assert_true(code.contains("wrap_controls = false"), "必须显式关闭 wrap_controls")
	assert_true(code.contains("screen_get_usable_rect"), "窗口尺寸必须按屏幕可用区夹紧")