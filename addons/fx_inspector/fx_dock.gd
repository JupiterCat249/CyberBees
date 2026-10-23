@tool
extends VBoxContainer
## Fx Inspector 面板主体（@tool ⇒ 编辑器里可交互）
##
## 结构：资源选择行 → 参数摘要 → **实时样例**（按真实 float_text.tscn 渲染两条样例浮字）
##   · 样例 1：伤害/抵挡（preview_hint_damage_color + 字号 + 偏移）
##   · 样例 2：反击（preview_hint_counter_color）
##   · 修改资源字段后按"刷新"或重新选中资源即可看到变化（编辑器不跑游戏逻辑）。

const FLOAT_SCENE := preload("res://scenes/ui/float_text.tscn")
const DEFAULT_PATH := "res://game_data/fx/fx_params.tres"

var _params: Resource = null
var _path_edit: LineEdit = null
var _preview: Control = null
var _info: Label = null
var _err: Label = null


func _ready() -> void:
	custom_minimum_size = Vector2(260, 240)
	add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "Fx 参数预览"
	title.add_theme_font_size_override("font_size", 14)
	add_child(title)
	_path_edit = LineEdit.new()
	_path_edit.text = DEFAULT_PATH
	_path_edit.tooltip_text = "FxParams 资源路径（默认 game_data/fx/fx_params.tres）"
	add_child(_path_edit)
	var row := HBoxContainer.new()
	add_child(row)
	var load_btn := Button.new()
	load_btn.text = "加载"
	load_btn.pressed.connect(_on_load)
	row.add_child(load_btn)
	var refresh_btn := Button.new()
	refresh_btn.text = "刷新样例"
	refresh_btn.pressed.connect(_refresh)
	row.add_child(refresh_btn)
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
	_preview = Control.new()
	_preview.custom_minimum_size = Vector2(0, 120)
	_preview.clip_contents = true
	add_child(_preview)
	_on_load()


## 外部（EditorPlugin._edit）把选中的资源送进来
func set_params(p: Resource) -> void:
	if p == null:
		return
	_params = p
	if _path_edit != null and p.resource_path != "":
		_path_edit.text = p.resource_path
	_refresh()


## 用编辑器文件对话框挑 FxParams（Dock 独立可用，不依赖 Inspector 选中）
func _on_pick() -> void:
	var dlg := EditorFileDialog.new()
	dlg.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dlg.access = EditorFileDialog.ACCESS_RESOURCES
	dlg.add_filter("*.tres", "资源")
	dlg.file_selected.connect(func(p: String) -> void:
		_path_edit.text = p
		_on_load())
	add_child(dlg)
	dlg.popup_centered_ratio(0.5)


func _on_load() -> void:
	_err.text = ""
	var path := _path_edit.text.strip_edges()
	if not ResourceLoader.exists(path):
		_err.text = "资源不存在：%s" % path
		return
	_params = load(path)
	if _params == null:
		_err.text = "加载失败：%s" % path
		return
	_refresh()


func _refresh() -> void:
	if _preview == null:
		return
	for ch in _preview.get_children():
		ch.queue_free()
	if _params == null:
		_info.text = "（未加载资源）"
		return
	_info.text = "字号 %d · 提示偏移 %s · 伤害色 %s · 反击色 %s" % [
		int(_params.preview_hint_font_size), str(_params.preview_hint_offset),
		str(_params.preview_hint_damage_color), str(_params.preview_hint_counter_color)]
	## 样例：两条浮字（与游戏内 view_fx.preview_hint 的呈现一致：字号 + 颜色 + 偏移）
	_sample("抵挡", _params.preview_hint_damage_color, Vector2(30, 30))
	_sample("反击 -3", _params.preview_hint_counter_color, Vector2(150, 70))


func _sample(text: String, color: Color, pos: Vector2) -> void:
	var ft: Control = FLOAT_SCENE.instantiate()
	var lb := ft.get_node_or_null("Text") as Label
	if lb != null:
		lb.text = text
		lb.modulate = color
		lb.add_theme_font_size_override("font_size", int(_params.preview_hint_font_size))
	_preview.add_child(ft)
	ft.position = pos
