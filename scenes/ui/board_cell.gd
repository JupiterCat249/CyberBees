extends Control
## BoardCell —— 棋盘格点击代理（**纯交互节点，不绘制任何内容**）
##
## 为什么需要它：棋盘底图与特殊地形图标**由地图素材自带**（项目既定口径），
## 游戏内不额外绘制格子视觉；但**点击需要命中区**，故用无视觉的 Control 铺在格位上。
## 坐标空间：`Battle/MapView`（单位卡容器 `Units` 也在同一空间）
##
## ⚠️ 坐标约定：Vector2i(cell.x = 行, cell.y = 列)；格宽 = UNIT_PITCH(250)

signal cell_clicked(cell: Vector2i)
signal cell_right_clicked(cell: Vector2i)

var cell: Vector2i = Vector2i.ZERO
var highlight: String = ""      ## "" | "move" | "attack" | "deploy" | "deny"
var selected: bool = false

## ⭐ 特殊地形（迭代059 步3）：视图把地形效果/渲染参数**灌进来**，格子只负责画
##    —— 格子不自己去查地图，规则数据由 arena_view 下发（保持单向分层）
var terrain_tint: Color = Color(0, 0, 0, 0)      ## a=0 表示无地形
var terrain_icon: Texture2D = null
var terrain_params: TerrainParams = null
var terrain_name: String = ""

## ⚠️ 迭代064 B4（修 P-13 = 清单 UI-17「移动/攻击的可选对象 UI 标记没有看到」）：
##   原 alpha 仅 **0.28~0.35**，叠在**橄榄绿地形贴图**上几乎不可辨 —— 提高不透明度并**加内描边**，
##   使其在花哨地形上也能一眼分辨。
##   （"有单位"的格不靠这里：`PITCH = 250` 而单位卡正好 250×250，会把格上的高亮**整片盖住** ——
##     故攻击/支援目标改用**卡上标框** `card_unit.gd::set_mark()`。）
const _COL_MOVE := Color(0.25, 0.95, 0.50, 0.46)
const _COL_ATTACK := Color(1.0, 0.36, 0.28, 0.48)
const _COL_DEPLOY := Color(0.30, 0.75, 1.0, 0.46)
const _COL_SEL := Color(1.0, 1.0, 1.0, 0.50)
## 内描边色（比填充更亮，避免在同类色地形上糊在一起）
const _COL_MOVE_EDGE := Color(0.45, 1.0, 0.65, 0.95)
const _COL_ATTACK_EDGE := Color(1.0, 0.55, 0.45, 0.95)
const _COL_DEPLOY_EDGE := Color(0.55, 0.85, 1.0, 0.95)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			cell_clicked.emit(cell)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			cell_right_clicked.emit(cell)
			accept_event()


func set_highlight(kind: String) -> void:
	if highlight != kind:
		highlight = kind
		queue_redraw()


func set_selected(v: bool) -> void:
	if selected != v:
		selected = v
		queue_redraw()


func set_terrain(effect: TerrainEffect, params: TerrainParams) -> void:
	terrain_params = params
	if effect == null:
		terrain_tint = Color(0, 0, 0, 0)
		terrain_icon = null
		terrain_name = ""
	else:
		terrain_tint = effect.tint
		terrain_icon = effect.icon
		terrain_name = effect.display_name
		if terrain_tint.a <= 0.0:
			terrain_tint = Color(1, 1, 1, 0.25)
	queue_redraw()


## 该格是否有可见地形
func has_terrain() -> bool:
	return terrain_tint.a > 0.0


func _draw() -> void:
	## ① 地形底（**仅在 draw_marker 打开时画** —— 人明确：地图素材自带地形，代码不画标记）
	if has_terrain() and terrain_params != null and terrain_params.draw_marker:
		var p := terrain_params
		draw_rect(Rect2(Vector2.ZERO, size), p.fill_color_from(terrain_tint), true)
		if p.outline:
			draw_rect(p.outline_rect(size.x), p.outline_color, false, p.outline_width)
		if terrain_icon != null:
			var isz: Vector2 = p.icon_size
			draw_texture_rect(terrain_icon, Rect2(p.icon_offset(size.x), isz), false,
				Color(1, 1, 1, p.icon_alpha))
	## ② 选中/高亮
	if selected:
		draw_rect(Rect2(Vector2.ZERO, size), _COL_SEL, true)
	## ⚠️ 迭代064 B4：单靠半透明填充在花哨地形上看不出来 → **填充 + 3px 内描边**
	var rc := Rect2(Vector2.ZERO, size)
	match highlight:
		"move":
			draw_rect(rc, _COL_MOVE, true)
			draw_rect(rc, _COL_MOVE_EDGE, false, 3.0)
		"attack":
			draw_rect(rc, _COL_ATTACK, true)
			draw_rect(rc, _COL_ATTACK_EDGE, false, 3.0)
		"deploy":
			draw_rect(rc, _COL_DEPLOY, true)
			draw_rect(rc, _COL_DEPLOY_EDGE, false, 3.0)
		"deny":
			draw_rect(rc, Color(0.5, 0.5, 0.5, 0.22), true)
			draw_rect(rc, Color(0.5, 0.5, 0.5, 0.5), false, 3.0)
