extends Node
## 【工具 · 非生产】运行环境自检 —— **检测"异机差异"的取证工具**（F6 直接运行，不依赖游戏逻辑）
## ---------------------------------------------------------------------------
## 为什么需要：本项目 UI 坐标是设计分辨率 1920×1080 下的**绝对像素**，而实际渲染区
##   由「窗口尺寸 × 屏幕 × 系统缩放 × stretch 设置」共同决定 ⇒ **异机必然可能不同**。
##   本工具把**所有会影响画面的环境量**一次性打印并落盘，用于把两台机器的差异摆在同一条线上比对。
##
## 用法（任意机器）：
##   ① 编辑器里 F6 运行本场景；或游戏运行中按 **F8**（见 `arena_view.dump_runtime_geometry`）
##   ② 读输出面板（同时落盘 `user://diag/selfcheck_<时间戳>.txt`）
##   ③ 换窗口尺寸 / 全屏 / 改显示缩放后**再跑一次**，比对差异
## 一切数值都来自引擎实际 API（不靠假设、不靠硬编码）。
## ---------------------------------------------------------------------------
const OUT_DIR := "user://diag"

var _lines: PackedStringArray = []


func _log(s: String) -> void:
	print(s)
	_lines.append(s)


func _ready() -> void:
	_log("========== 🔍 ENV SELF-CHECK（运行环境自检）==========")
	_check_engine()
	_check_screen()
	_check_window()
	_check_stretch()
	_check_editor_settings()
	_check_project_plugins()
	_check_godot_dir()
	_save()
	_log("=================================================")
	get_tree().quit()


func _check_engine() -> void:
	_log("[引擎/系统]")
	_log("  Godot        : %s" % str(Engine.get_version_info().get("string", "?")))
	_log("  build/hash   : %s" % str(Engine.get_version_info().get("hash", "?")))
	_log("  OS           : %s · %s · %s" % [OS.get_name(), OS.get_version(), OS.get_processor_name()])
	_log("  OS 语言/区域 : %s / %s" % [OS.get_locale(), OS.get_locale_language()])
	_log("  display 驱动 : %s" % DisplayServer.get_name())


func _check_screen() -> void:
	_log("[屏幕/DPI/缩放] —— 影响「逻辑宽度」的关键组")
	var n := DisplayServer.get_screen_count()
	_log("  屏幕数量      : %d" % n)
	for i in n:
		_log("    screen[%d] size=%s usable=%s scale=%.2f dpi=%d refresh=%.2f" % [
			i, str(DisplayServer.screen_get_size(i)), str(DisplayServer.screen_get_usable_rect(i)),
			DisplayServer.screen_get_scale(i), DisplayServer.screen_get_dpi(i),
			DisplayServer.screen_get_refresh_rate(i)])
	_log("  当前屏(默认)  : size=%s scale=%.2f dpi=%d" % [
		str(DisplayServer.screen_get_size()), DisplayServer.screen_get_scale(),
		DisplayServer.screen_get_dpi()])
	_log("  ⭐ 逻辑桌面宽 : %.0f px（＝物理宽 %.0f ÷ scale %.2f）—— 底部面板带被顶掉常见于逻辑宽过小" % [
		float(DisplayServer.screen_get_size().x) / maxf(0.01, DisplayServer.screen_get_scale()),
		float(DisplayServer.screen_get_size().x), DisplayServer.screen_get_scale()])


func _check_window() -> void:
	_log("[窗口]")
	var w := get_window()
	_log("  窗口 size=%s pos=%s mode=%d current_screen=%d" % [
		str(w.size), str(w.position), int(w.mode), int(w.current_screen)])
	_log("  content_scale_size=%s  content_scale_mode=%d  content_scale_aspect=%d" % [
		str(w.content_scale_size), int(w.content_scale_mode), int(w.content_scale_aspect)])
	_log("  视口 visible_rect=%s" % str(get_viewport().get_visible_rect()))


func _check_stretch() -> void:
	_log("[项目显示设置（project.godot）]")
	for k in ["display/window/size/viewport_width", "display/window/size/viewport_height",
			"display/window/size/window_width_override", "display/window/size/window_height_override",
			"display/window/size/mode", "display/window/size/resizable",
			"display/window/stretch/mode", "display/window/stretch/aspect", "display/window/stretch/scale",
			"display/window/stretch/scale_mode", "run/max_fps",
			"rendering/renderer/rendering_method"]:
		_log("  %-52s = %s" % [String(k), str(ProjectSettings.get_setting(k, "<未设置>"))])


func _check_editor_settings() -> void:
	_log("[编辑器设置（不在仓库，每台机一份）]")
	var vi := Engine.get_version_info()
	var cands: Array[String] = [
		"%s/editor_settings-%d.%d.tres" % [OS.get_data_dir(), int(vi.major), int(vi.minor)],
		"%s/editor_settings-%d.%d.tres" % [
			OS.get_data_dir().path_join("Godot"), int(vi.major), int(vi.minor)],
	]
	var f: FileAccess = null
	var p := ""
	for c in cands:
		f = FileAccess.open(c, FileAccess.READ)
		if f != null:
			p = c
			break
	if f == null:
		_log("  ⚠ 读不到编辑器设置（外部/导出运行属正常）：尝试过 %s" % str(cands))
		return
	var txt := f.get_as_text()
	f.close()
	for key in ["interface/editor/appearance/display_scale",
			"interface/editor/appearance/custom_display_scale",
			"interface/editor/appearance/editor_screen",
			"interface/editor/appearance/project_manager_screen",
			"run/window_placement/screen", "run/window_placement/rect",
			"run/window_placement/game_embed_mode",
			"interface/editor/appearance/use_embedded_menu"]:
		var val := "<未设>"
		for line in txt.split("\n"):
			if String(line).begins_with(String(key) + " ="):
				var parts := String(line).split("=", false, 1)
				if parts.size() > 1:
					val = String(parts[1]).strip_edges()
				break
		_log("  %-56s = %s" % [String(key), val])
	_log("  文件：%s" % p)


func _check_project_plugins() -> void:
	_log("[项目：插件启用清单]")
	var plugins = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
	for p in plugins:
		_log("  插件 : %s" % str(p))
	var autoloads: Array[String] = []
	for k in ProjectSettings.get_property_list():
		var nm := String(k.get("name", ""))
		if nm.begins_with("autoload/"):
			autoloads.append("%s = %s" % [nm, str(ProjectSettings.get_setting(nm))])
	_log("  自动加载(%d)：%s" % [autoloads.size(), str(autoloads)])


func _check_godot_dir() -> void:
	_log("[项目内 .godot 缓存（用于判断停靠布局是否异常）]")
	var layout := "res://.godot/editor/editor_layout.cfg"
	var f := FileAccess.open(layout, FileAccess.READ)
	if f == null:
		_log("  ⚠ 无 %s（首次运行或已清理 ⇒ 会自动重建默认布局）" % layout)
		return
	var txt := f.get_as_text()
	f.close()
	for line in txt.split("\n"):
		var l := String(line).strip_edges()
		if l.begins_with("dock_split") or l.begins_with("dock_hsplit"):
			_log("  %s" % l)


func _save() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-")
	var path := "%s/selfcheck_%s.txt" % [OUT_DIR, stamp]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("  ⚠ 写盘失败：%s" % path)
		return
	f.store_string("\n".join(_lines))
	f.close()
	_log("📄 报告已落盘：%s" % ProjectSettings.globalize_path(path))
	_log("📸 看画面实际渲染区与节点越界：游戏运行中调 `arena_view.dump_runtime_geometry()`")
