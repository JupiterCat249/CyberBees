@tool
extends Node2D
## ============================================================
## Shader 自动卡牌：1 个 shader + 1 张图集渲染整张卡（250x250）
##
## 使用（实例化 card_auto.tscn 后，只改检查器参数，不动内部节点）：
##   ① 「素材」art     → 拖入中央立绘（card_system/art/ 内 10 张）
##      「素材」tag_texture → 可选，自定义右上角类别图标（card_system/tag_icons/）
##   ② 「图标」icon_tag → 右上角类别图标（-1无 0攻击 1速度 2血量 3射程 4兵蜂 5建筑 6指令 7蜂王）
##   ③ 「数字」cost / stat_* → 5 个数值（-1 = 不显示，>=10 自动两位）
## 大量渲染：参考 card_demo.tscn —— 数据数组批量实例化，每张卡只填参数
## ============================================================

# ---------------- 数字（-1 = 不显示） ----------------
@export_group("数字（-1=不显示）")
@export_range(-1, 99) var cost := 6: set = set_cost
@export_range(-1, 99) var stat_l1 := 5: set = set_stat_l1
@export_range(-1, 99) var stat_l2 := -1: set = set_stat_l2
@export_range(-1, 99) var stat_r1 := -1: set = set_stat_r1
@export_range(-1, 99) var stat_r2 := 3: set = set_stat_r2

# ---------------- 图标 ----------------
@export_group("图标：-1无 0攻击 1速度 2血量 3射程 4兵蜂 5建筑 6指令 7蜂王")
@export_range(-1, 7) var icon_l1 := 0: set = set_icon_l1
@export_range(-1, 7) var icon_l2 := 1: set = set_icon_l2
@export_range(-1, 7) var icon_r1 := 2: set = set_icon_r1
@export_range(-1, 7) var icon_r2 := 3: set = set_icon_r2
@export_range(-1, 7) var icon_tag := 6: set = set_icon_tag

# ---------------- 素材 ----------------
@export_group("素材")
@export var art: Texture2D: set = set_art                # 中央立绘
@export var tag_texture: Texture2D: set = set_tag_texture  # 自定义类别图标（优先于 icon_tag）
@export_range(0, 1) var art_fit := 1: set = set_art_fit    # 1=裁剪铺满（立绘撑满中央区，默认） 0=完整显示
@export_range(1.0, 2.0, 0.01) var art_zoom := 1.0: set = set_art_zoom  # 立绘放大（裁掉素材边缘留白，角色更大）

# ---------------- 配色 ----------------
@export_group("配色")
@export var col_base := Color.WHITE: set = set_col_base               # 卡底
@export var col_cell := Color(0.8, 0.8, 0.8): set = set_col_cell      # 数值/图标格
@export var col_band := Color(0.56, 0.56, 0.56): set = set_col_band   # 横带+分隔条
@export var col_cost_bg := Color(0.16, 0.16, 0.16): set = set_col_cost_bg
@export var col_cost_num := Color(0.96, 0.62, 0.04): set = set_col_cost_num
@export var col_num := Color(0.3, 0.3, 0.3): set = set_col_num
@export var col_icon := Color(0.42, 0.42, 0.42): set = set_col_icon    # 侧栏图标（深灰）
@export var col_tag_bg := Color(0.55, 0.55, 0.55): set = set_col_tag_bg
@export var col_tag_icon := Color(0.78, 0.78, 0.78): set = set_col_tag_icon
@export var col_center := Color(0.93, 0.93, 0.93): set = set_col_center
@export var col_stripe := Color(0.87, 0.87, 0.87): set = set_col_stripe

# ---------------- 微调 ----------------
@export_group("微调")
@export_range(0.3, 1.0, 0.01) var icon_scale := 0.74: set = set_icon_scale
@export_range(0.3, 1.0, 0.01) var tag_icon_scale := 0.78: set = set_tag_icon_scale


func _ready() -> void:
	_apply_all()


# ---------------- 内部实现（正常使用不用看） ----------------

func _sp(n: String, v: Variant) -> void:
	if is_node_ready():
		var m := $Rect.material as ShaderMaterial
		if m != null:
			m.set_shader_parameter(n, v)

func set_cost(v: int) -> void:
	cost = v
	_sp("cost_num", v)

func set_stat_l1(v: int) -> void:
	stat_l1 = v
	_sp("num_l1", v)

func set_stat_l2(v: int) -> void:
	stat_l2 = v
	_sp("num_l2", v)

func set_stat_r1(v: int) -> void:
	stat_r1 = v
	_sp("num_r1", v)

func set_stat_r2(v: int) -> void:
	stat_r2 = v
	_sp("num_r2", v)

func set_icon_l1(v: int) -> void:
	icon_l1 = v
	_sp("icon_l1", v)

func set_icon_l2(v: int) -> void:
	icon_l2 = v
	_sp("icon_l2", v)

func set_icon_r1(v: int) -> void:
	icon_r1 = v
	_sp("icon_r1", v)

func set_icon_r2(v: int) -> void:
	icon_r2 = v
	_sp("icon_r2", v)

func set_icon_tag(v: int) -> void:
	icon_tag = v
	_sp("icon_tag", v)

func set_art(v: Texture2D) -> void:
	art = v
	if is_node_ready():
		_sp("art_tex", v)
		_sp("has_art", 1 if v != null else 0)
		_sp("art_size", Vector2(v.get_width(), v.get_height()) if v != null else Vector2(1, 1))

func set_tag_texture(v: Texture2D) -> void:
	tag_texture = v
	if is_node_ready():
		_sp("tag_tex", v)
		_sp("tag_mode", 1 if v != null else 0)
		_sp("tag_size", Vector2(v.get_width(), v.get_height()) if v != null else Vector2(1, 1))

func set_art_fit(v: int) -> void:
	art_fit = v
	_sp("art_fit", v)

func set_art_zoom(v: float) -> void:
	art_zoom = v
	_sp("art_zoom", v)

func set_col_base(v: Color) -> void:
	col_base = v
	_sp("col_base", v)

func set_col_cell(v: Color) -> void:
	col_cell = v
	_sp("col_cell", v)

func set_col_band(v: Color) -> void:
	col_band = v
	_sp("col_band", v)

func set_col_cost_bg(v: Color) -> void:
	col_cost_bg = v
	_sp("col_cost_bg", v)

func set_col_cost_num(v: Color) -> void:
	col_cost_num = v
	_sp("col_cost_num", v)

func set_col_num(v: Color) -> void:
	col_num = v
	_sp("col_num", v)

func set_col_icon(v: Color) -> void:
	col_icon = v
	_sp("col_icon", v)

func set_col_tag_bg(v: Color) -> void:
	col_tag_bg = v
	_sp("col_tag_bg", v)

func set_col_tag_icon(v: Color) -> void:
	col_tag_icon = v
	_sp("col_tag_icon", v)

func set_col_center(v: Color) -> void:
	col_center = v
	_sp("col_center", v)

func set_col_stripe(v: Color) -> void:
	col_stripe = v
	_sp("col_stripe", v)

func set_icon_scale(v: float) -> void:
	icon_scale = v
	_sp("icon_scale", v)

func set_tag_icon_scale(v: float) -> void:
	tag_icon_scale = v
	_sp("tag_icon_scale", v)

func _apply_all() -> void:
	set_cost(cost)
	set_stat_l1(stat_l1)
	set_stat_l2(stat_l2)
	set_stat_r1(stat_r1)
	set_stat_r2(stat_r2)
	set_icon_l1(icon_l1)
	set_icon_l2(icon_l2)
	set_icon_r1(icon_r1)
	set_icon_r2(icon_r2)
	set_icon_tag(icon_tag)
	set_art(art)
	set_tag_texture(tag_texture)
	set_art_fit(art_fit)
	set_art_zoom(art_zoom)
	set_col_base(col_base)
	set_col_cell(col_cell)
	set_col_band(col_band)
	set_col_cost_bg(col_cost_bg)
	set_col_cost_num(col_cost_num)
	set_col_num(col_num)
	set_col_icon(col_icon)
	set_col_tag_bg(col_tag_bg)
	set_col_tag_icon(col_tag_icon)
	set_col_center(col_center)
	set_col_stripe(col_stripe)
	set_icon_scale(icon_scale)
	set_tag_icon_scale(tag_icon_scale)
