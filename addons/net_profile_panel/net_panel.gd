@tool
extends VBoxContainer
## 「联机档位」停靠面板 —— 在编辑器里**可视化查看与切换**运行档位
## ---------------------------------------------------------------------------
## 起因：运行档位原本只由纯文本开关文件 `res://net_config/profile.flag` 决定，
##       编辑器里既看不到也改不了 → 容易"改了没生效 / 不知道现在连哪台"。
## 写盘行为（切换档位时）：**同时**写
##   · `ProjectSettings net/profile`（引擎自带持久化，进 project.godot；项目设置面板也能看/改）
##   · `res://net_config/profile.flag`（旧机制同步，避免两个来源打架）
## 自动模式：`res://net_config/auto.flag` = 1/0（连上即入队、配对即进对局；验收/双实例用）
## 档位解析优先级：见 `scripts/net/net_config.gd::default_profile()`
## ⚠️ 本脚本只在**编辑器进程**内运行（`@tool`），不进入导出产物。

const NC := preload("res://scripts/net/net_config.gd")

var plugin: EditorPlugin = null

var _opt: OptionButton = null
var _url_label: Label = null
var _src_label: Label = null
var _auto_check: CheckBox = null
var _last_key: String = ""
var _loading: bool = false


func _ready() -> void:
	name = "联机档位"
	_build()
	_refresh(true)
	var t := Timer.new()
	t.name = "WatchTimer"
	t.wait_time = 2.0
	t.autostart = true
	t.timeout.connect(_on_watch)
	add_child(t)


func _build() -> void:
	var title := Label.new()
	title.text = "联机运行档位"
	title.add_theme_font_size_override("font_size", 15)
	add_child(title)

	var row := HBoxContainer.new()
	var lab := Label.new()
	lab.text = "档位"
	row.add_child(lab)
	_opt = OptionButton.new()
	_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_opt.tooltip_text = "切换后同时写入 ProjectSettings net/profile 与 net_config/profile.flag"
	_opt.item_selected.connect(_on_selected)
	row.add_child(_opt)
	add_child(row)

	_url_label = Label.new()
	_url_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_url_label.add_theme_font_size_override("font_size", 11)
	add_child(_url_label)

	_src_label = Label.new()
	_src_label.add_theme_font_size_override("font_size", 11)
	add_child(_src_label)

	_auto_check = CheckBox.new()
	_auto_check.text = "自动模式（连上即入队、配对即进对局）"
	_auto_check.add_theme_font_size_override("font_size", 11)
	_auto_check.tooltip_text = "写 net_config/auto.flag；双实例自动验收用，人工测试请保持关闭"
	_auto_check.toggled.connect(_on_auto_toggled)
	add_child(_auto_check)

	var btns := HBoxContainer.new()
	var b_refresh := Button.new()
	b_refresh.text = "刷新"
	b_refresh.pressed.connect(_on_refresh_pressed)
	btns.add_child(b_refresh)
	var b_open := Button.new()
	b_open.text = "打开目录"
	b_open.tooltip_text = "在文件管理器里打开 net_config/"
	b_open.pressed.connect(_on_open_dir)
	btns.add_child(b_open)
	add_child(btns)

	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 10)
	hint.modulate = Color(1, 1, 1, 0.65)
	hint.text = "F6 运行的实例按此档位连接；命令行 --net-profile= 与 SB_NET_PROFILE 优先级更高。"
	add_child(hint)


## 每 2 秒自检一次外部改动（git checkout / MCP 写入 / 手工改文件）→ 面板显示始终等于真实值
func _on_watch() -> void:
	_refresh(false)


func _refresh(force: bool) -> void:
	var profs := NC.profiles()
	var cur := NC.default_profile()
	var auto_on := _read_auto()
	var key := "%s|%s|%s" % [cur, str(profs), str(auto_on)]
	if not force and key == _last_key:
		return
	_last_key = key

	var need_rebuild := _opt.item_count != profs.size()
	if not need_rebuild:
		for i in profs.size():
			if _opt.get_item_text(i) != profs[i]:
				need_rebuild = true
				break
	_loading = true
	if need_rebuild:
		_opt.clear()
		for p in profs:
			_opt.add_item(p)
	var idx := profs.find(cur)
	if idx >= 0:
		_opt.select(idx)
	else:
		_opt.selected = -1
	_loading = false

	if profs.has(cur):
		var cfg := NC.load_profile(cur)
		_url_label.text = "→ %s" % NC.resolve_url(cfg)
	else:
		_url_label.text = "→ （缺 res://net_config/net.%s.json）" % cur
	_src_label.text = "来源：%s" % NC.profile_source()
	_auto_check.set_pressed_no_signal(auto_on)


func _on_refresh_pressed() -> void:
	_refresh(true)
	print("[NET-PANEL] 手动刷新：档位=%s 来源=%s" % [NC.default_profile(), NC.profile_source()])


func _on_open_dir() -> void:
	OS.shell_open(ProjectSettings.globalize_path(NC.DIR))


func _on_selected(idx: int) -> void:
	if _loading or idx < 0:
		return
	var picked := _opt.get_item_text(idx)
	ProjectSettings.set_setting(NC.SETTING, picked)
	ProjectSettings.save()
	_write_text_file(NC.DIR + "/profile.flag", picked)
	print("[NET-PANEL] 档位 → %s（已写 ProjectSettings %s 与 net_config/profile.flag）" % [picked, NC.SETTING])
	_refresh(true)


func _on_auto_toggled(on: bool) -> void:
	_write_text_file(NC.DIR + "/auto.flag", "1" if on else "0")
	print("[NET-PANEL] 自动模式 → %s" % ("开" if on else "关"))
	_refresh(true)


func _read_auto() -> bool:
	var p := NC.DIR + "/auto.flag"
	if not FileAccess.file_exists(p):
		return false
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return false
	var v := f.get_as_text().strip_edges().to_lower()
	f.close()
	return v == "1" or v == "true" or v == "on"


func _write_text_file(path: String, content: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[NET-PANEL] 写入失败 %s（err=%d）" % [path, FileAccess.get_open_error()])
		return
	f.store_string(content)
	f.close()
