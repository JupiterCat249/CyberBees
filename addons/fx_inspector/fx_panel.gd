@tool
extends VBoxContainer
## FxParams 预览面板（迭代147：改为**独立窗口**里的面板，不再注册 Dock）
##
## 设计约束（都来自实测教训）
##   · 不依赖 Inspector 选中（选中联动属 main-screen 三件套，会接管主工作区）；
##   · 不实例化游戏场景（编辑器里跑游戏 UI 容易连带布局问题）；
##   · 所有控件可收缩（ScrollContainer 兜底），窗口关掉即释放。

const DEFAULT_PATH := "res://game_data/fx/fx_params.tres"

var _params: Resource = null
var _path_edit: LineEdit = null
var _info: Label = null
var _err: Label = null
var _canvas: Control = null


func _ready() -> void:
	## 作为 Window 的直接子节点：**铺满窗口**（不反向撑窗口）
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "Fx 参数预览"
	title.add_theme_font_size_override("font_size", 14)
	add_child(title)
	var row := HBoxContainer.new()
	add_child(row)
	_path_edit = LineEdit.new()
	_path_edit.text = DEFAULT_PATH
	_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_path_edit)
	var load_btn := Button.new()
	load_btn.text = "加载"
	load_btn.pressed.connect(_on_load)
	row.add_child(load_btn)
	var pick_btn := Button.new()
	pick_btn.text = "选择…"
	pick_btn.pressed.connect(_on_pick)
	row.add_child(pick_btn)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_info)
	_err = Label.new()
	_err.modulate = Color(1, 0.4, 0.3)
	_err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_err)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	_canvas = Control.new()
	## 只给"示例画布"一个**小的**最小高度；不给大值，避免再次反向撑窗口
	_canvas.custom_minimum_size = Vector2(0, 140)
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_canvas)
	_on_load()


func _on_load() -> void:
	if _err != null:
		_err.text = ""
	var path := _path_edit.text.strip_edges()
	if not ResourceLoader.exists(path):
		if _err != null:
			_err.text = "资源不存在：%s" % path
		return
	_params = load(path)
	_refresh()


func _on_pick() -> void:
	var dlg := EditorFileDialog.new()
	dlg.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dlg.access = EditorFileDialog.ACCESS_RESOURCES
	dlg.add_filter("*.tres", "资源")
	dlg.file_selected.connect(func(p: String) -> void:
		_path_edit.text = p
		_on_load()
		dlg.queue_free())
	dlg.canceled.connect(func() -> void: dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered_ratio(0.5)


func _refresh() -> void:
	if _canvas == null:
		return
	for ch in _canvas.get_children():
		ch.queue_free()
	if _params == null:
		if _info != null:
			_info.text = "（未加载资源）"
		return
	if _info != null:
		_info.text = "提示字号 %d · 提示偏移 %s · 伤害色 %s · 反击色 %s" % [
			int(_params.preview_hint_font_size), str(_params.preview_hint_offset),
			str(_params.preview_hint_damage_color), str(_params.preview_hint_counter_color)]
	_sample("抵挡", _params.preview_hint_damage_color, Vector2(24, 20))
	_sample("反击 -3", _params.preview_hint_counter_color, Vector2(160, 70))
	_sample("-4 击杀", _params.preview_hint_damage_color, Vector2(24, 120))


## 用**普通 Label** 画样例（与游戏里 view_fx.preview_hint 呈现同参：字号 + 颜色）
func _sample(text: String, color: Color, pos: Vector2) -> void:
	var lb := Label.new()
	lb.text = text
	lb.modulate = color
	lb.add_theme_font_size_override("font_size", int(_params.preview_hint_font_size))
	lb.position = pos
	_canvas.add_child(lb)
