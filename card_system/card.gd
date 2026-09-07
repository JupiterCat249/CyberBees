@tool
extends Node2D
## ============================================================
## 卡牌整体（一个场景 = 一张完整的卡）
## 图标全部使用 PNG 素材（res://card_system/icons/），零 shader 依赖
##
## 使用规则：
##   1. 只改根节点 Card 的检查器参数，不要手动拖动内部节点
##      （排版由本脚本在加载时强制重建，拖乱了重新加载即恢复）
##   2. 屏幕上多渲染卡 = 把 card_base.tscn 实例化多次，每张独立改参数
##   3. 合作伙伴导入素材：立绘拖到 art 参数，自定义标签拖到 tag_texture
## ============================================================

# ---------------- 排版常量（250x250 设计坐标系，比例取自目标效果图） ----------------
# 侧栏行分布（行间 2px 白隙，露出卡底色）：
#   0-43    费用/标签格
#   43-62   横带1
#   64-100  数值1
#   102-138 图标1
#   140-158 分隔条
#   160-196 数值2
#   198-234 图标2
#   236-250 横带2
const CARD_W := 250.0
const COL_W := 40.0            # 左右侧栏宽
const COL_R_X := 210.0         # 右栏 x 起点
const CORNER_R := 10.0         # 四角圆角半径

const H_COST := 43.0           # 费用/标签格高
const Y_BAND1 := 43.0
const H_BAND1 := 19.0
const Y_NUM1 := 64.0
const H_TILE := 36.0           # 数值/图标格高
const Y_ICON1 := 102.0
const Y_SEP := 140.0
const H_SEP := 18.0
const Y_NUM2 := 160.0
const Y_ICON2 := 198.0
const Y_BAND2 := 236.0
const H_BAND2 := 14.0

# 数字 Label 比格子高（容纳字体行高），垂直居中补偿用
const LABEL_H_COST := 56.0
const LABEL_H_STAT := 52.0

# 图标素材（白色剪影，用 self_modulate 染色）
const ICON_TEX := {
	0: preload("res://card_system/icons/attack.png"),    # 攻击·剑
	1: preload("res://card_system/icons/speed.png"),     # 速度·三重箭
	2: preload("res://card_system/icons/hp.png"),        # 血量·U 形杯
	3: preload("res://card_system/icons/range.png"),     # 射程·准星
	5: preload("res://card_system/icons/soldier.png"),   # 兵蜂
	6: preload("res://card_system/icons/building.png"),  # 建筑
	7: preload("res://card_system/icons/command.png"),   # 指令·六边形
	8: preload("res://card_system/icons/queen.png"),     # 蜂王·皇冠
}

# ---------------- 可调参数（检查器，改完立即生效） ----------------
@export_group("调色板")
@export var col_center := Color(1.0, 1.0, 1.0):        # 整卡底色（含圆角）
	set(v):
		col_center = v
		if _ready_ok():
			$CenterBg.get_theme_stylebox("panel").bg_color = v
@export var col_side := Color(0.80, 0.80, 0.80):       # 数值/图标格底色（独立浮块）
	set(v):
		col_side = v
		if _ready_ok():
			for n in [$CellL1, $CellL2, $CellL3, $CellL4, $CellR1, $CellR2, $CellR3, $CellR4]:
				n.color = v
@export var col_accent := Color(0.56, 0.56, 0.56):     # 横带 + 分隔条
	set(v):
		col_accent = v
		if _ready_ok():
			for n in [$Band1L, $Band1R, $SepL, $SepR]:
				n.color = v
			$Band2L.get_theme_stylebox("panel").bg_color = v
			$Band2R.get_theme_stylebox("panel").bg_color = v
@export var col_cost_bg := Color(0.08, 0.08, 0.08):    # 费用格底
	set(v):
		col_cost_bg = v
		if _ready_ok():
			$CostCell.get_theme_stylebox("panel").bg_color = v
@export var col_tag_bg := Color(0.58, 0.58, 0.58):     # 标签格底
	set(v):
		col_tag_bg = v
		if _ready_ok():
			$TagCell.get_theme_stylebox("panel").bg_color = v
@export var col_tag_icon := Color(0.75, 0.75, 0.75):   # 默认标签三角颜色
	set(v):
		col_tag_icon = v
		if _ready_ok():
			$TagTri.color = v
@export var col_icon := Color(0.30, 0.30, 0.30):       # 图标染色
	set(v):
		col_icon = v
		if _ready_ok():
			for n in [$IconL1, $IconL2, $IconR1, $IconR2, $TagIcon]:
				n.self_modulate = v
@export var col_cost_text := Color(0.96, 0.62, 0.04):  # 费用数字颜色
	set(v):
		col_cost_text = v
		if _ready_ok():
			$CostLabel.add_theme_color_override("font_color", v)
@export var col_stat_text := Color(0.30, 0.30, 0.30):  # 数值数字颜色
	set(v):
		col_stat_text = v
		if _ready_ok():
			for n in [$StatL1, $StatL2, $StatR1, $StatR2]:
				n.add_theme_color_override("font_color", v)

@export_group("数字")
@export var cost := 3:
	set(v):
		cost = v
		if _ready_ok():
			$CostLabel.text = str(v)
@export var stat_l1 := 3:
	set(v):
		stat_l1 = v
		if _ready_ok():
			$StatL1.text = str(v)
@export var stat_l2 := 1:
	set(v):
		stat_l2 = v
		if _ready_ok():
			$StatL2.text = str(v)
@export var stat_r1 := 3:
	set(v):
		stat_r1 = v
		if _ready_ok():
			$StatR1.text = str(v)
@export var stat_r2 := 2:
	set(v):
		stat_r2 = v
		if _ready_ok():
			$StatR2.text = str(v)

@export_group("图标类型：0攻击 1速度 2血量 3射程 4默认三角 5兵蜂 6建筑 7指令 8蜂王")
@export_range(0, 8) var icon_l1 := 0:
	set(v):
		icon_l1 = v
		if _ready_ok():
			_set_icon($IconL1, v)
@export_range(0, 8) var icon_l2 := 1:
	set(v):
		icon_l2 = v
		if _ready_ok():
			_set_icon($IconL2, v)
@export_range(0, 8) var icon_r1 := 2:
	set(v):
		icon_r1 = v
		if _ready_ok():
			_set_icon($IconR1, v)
@export_range(0, 8) var icon_r2 := 3:
	set(v):
		icon_r2 = v
		if _ready_ok():
			_set_icon($IconR2, v)
@export_range(0, 8) var tag_icon := 4:
	set(v):
		tag_icon = v
		if _ready_ok():
			_apply_tag()

@export_group("素材")
@export var art: Texture2D:                 # 中央立绘
	set(v):
		art = v
		if _ready_ok():
			$Art.texture = v
@export var tag_texture: Texture2D:         # 自定义标签图形（优先于内置）
	set(v):
		tag_texture = v
		if _ready_ok():
			_apply_tag()

func _ready() -> void:
	# 旧 Control 方案（已被 card_auto.* shader 方案取代）；
	# 场景节点不全时直接静默退出，避免编辑器刷错误
	if not has_node("CenterBg") or not has_node("CellL1"):
		return
	_apply_layout()
	_apply_all()

# 节点齐全才执行 setter 同步（防止旧场景/误挂脚本时报错）
func _ready_ok() -> bool:
	return is_node_ready() and has_node("CenterBg") and has_node("CellL1")

# ---------------- 内部实现（正常使用不用看） ----------------

func _set_icon(n: TextureRect, type: int) -> void:
	n.texture = ICON_TEX.get(type)
	n.visible = n.texture != null

func _apply_tag() -> void:
	if tag_texture != null:
		$TagTex.texture = tag_texture
		$TagTex.visible = true
		$TagIcon.visible = false
		$TagTri.visible = false
	elif tag_icon == 4:
		$TagTex.visible = false
		$TagIcon.visible = false
		$TagTri.visible = true
	else:
		$TagTex.visible = false
		$TagTri.visible = false
		$TagIcon.texture = ICON_TEX.get(tag_icon)
		$TagIcon.visible = $TagIcon.texture != null

func _place_rect(n: Control, r: Rect2) -> void:
	n.offset_left = r.position.x
	n.offset_top = r.position.y
	n.offset_right = r.position.x + r.size.x
	n.offset_bottom = r.position.y + r.size.y

# 排版强制重建（行分布常量见文件顶部，改常量即改算法）
func _apply_layout() -> void:
	_place_rect($CenterBg, Rect2(0.0, 0.0, CARD_W, CARD_W))
	# 数值/图标格（独立浮块，块间 2px 露出白底）
	_place_rect($CellL1, Rect2(0.0, Y_NUM1, COL_W, H_TILE))
	_place_rect($CellL2, Rect2(0.0, Y_ICON1, COL_W, H_TILE))
	_place_rect($CellL3, Rect2(0.0, Y_NUM2, COL_W, H_TILE))
	_place_rect($CellL4, Rect2(0.0, Y_ICON2, COL_W, H_TILE))
	_place_rect($CellR1, Rect2(COL_R_X, Y_NUM1, COL_W, H_TILE))
	_place_rect($CellR2, Rect2(COL_R_X, Y_ICON1, COL_W, H_TILE))
	_place_rect($CellR3, Rect2(COL_R_X, Y_NUM2, COL_W, H_TILE))
	_place_rect($CellR4, Rect2(COL_R_X, Y_ICON2, COL_W, H_TILE))
	# 横带与分隔条
	_place_rect($Band1L, Rect2(0.0, Y_BAND1, COL_W, H_BAND1))
	_place_rect($Band1R, Rect2(COL_R_X, Y_BAND1, COL_W, H_BAND1))
	_place_rect($SepL, Rect2(0.0, Y_SEP, COL_W, H_SEP))
	_place_rect($SepR, Rect2(COL_R_X, Y_SEP, COL_W, H_SEP))
	_place_rect($Band2L, Rect2(0.0, Y_BAND2, COL_W, H_BAND2))
	_place_rect($Band2R, Rect2(COL_R_X, Y_BAND2, COL_W, H_BAND2))
	# 费用格 / 标签格
	_place_rect($CostCell, Rect2(0.0, 0.0, COL_W, H_COST))
	_place_rect($TagCell, Rect2(COL_R_X, 0.0, COL_W, H_COST))
	$TagTri.position = Vector2(COL_R_X + COL_W * 0.5, H_COST * 0.5)
	_place_rect($TagIcon, Rect2(COL_R_X, 0.0, COL_W, H_COST))
	_place_rect($TagTex, Rect2(COL_R_X, 0.0, COL_W, H_COST))
	# 图标（数字正下方，同高）
	_place_rect($IconL1, Rect2(0.0, Y_ICON1, COL_W, H_TILE))
	_place_rect($IconL2, Rect2(0.0, Y_ICON2, COL_W, H_TILE))
	_place_rect($IconR1, Rect2(COL_R_X, Y_ICON1, COL_W, H_TILE))
	_place_rect($IconR2, Rect2(COL_R_X, Y_ICON2, COL_W, H_TILE))
	# 立绘
	_place_rect($Art, Rect2(COL_W, 0.0, CARD_W - COL_W * 2.0, CARD_W))
	# 数字（Label 加高居中补偿，避免行高钳制导致偏移）
	_place_rect($CostLabel, Rect2(0.0, (H_COST - LABEL_H_COST) * 0.5, COL_W, LABEL_H_COST))
	_place_rect($StatL1, Rect2(0.0, Y_NUM1 + (H_TILE - LABEL_H_STAT) * 0.5, COL_W, LABEL_H_STAT))
	_place_rect($StatR1, Rect2(COL_R_X, Y_NUM1 + (H_TILE - LABEL_H_STAT) * 0.5, COL_W, LABEL_H_STAT))
	_place_rect($StatL2, Rect2(0.0, Y_NUM2 + (H_TILE - LABEL_H_STAT) * 0.5, COL_W, LABEL_H_STAT))
	_place_rect($StatR2, Rect2(COL_R_X, Y_NUM2 + (H_TILE - LABEL_H_STAT) * 0.5, COL_W, LABEL_H_STAT))

func _apply_all() -> void:
	$CenterBg.get_theme_stylebox("panel").bg_color = col_center
	for n in [$CellL1, $CellL2, $CellL3, $CellL4, $CellR1, $CellR2, $CellR3, $CellR4]:
		n.color = col_side
	for n in [$Band1L, $Band1R, $SepL, $SepR]:
		n.color = col_accent
	$Band2L.get_theme_stylebox("panel").bg_color = col_accent
	$Band2R.get_theme_stylebox("panel").bg_color = col_accent
	$CostCell.get_theme_stylebox("panel").bg_color = col_cost_bg
	$TagCell.get_theme_stylebox("panel").bg_color = col_tag_bg
	$TagTri.color = col_tag_icon
	for n in [$IconL1, $IconL2, $IconR1, $IconR2, $TagIcon]:
		n.self_modulate = col_icon
	$CostLabel.add_theme_color_override("font_color", col_cost_text)
	for n in [$StatL1, $StatL2, $StatR1, $StatR2]:
		n.add_theme_color_override("font_color", col_stat_text)
	$CostLabel.text = str(cost)
	$StatL1.text = str(stat_l1)
	$StatL2.text = str(stat_l2)
	$StatR1.text = str(stat_r1)
	$StatR2.text = str(stat_r2)
	_set_icon($IconL1, icon_l1)
	_set_icon($IconL2, icon_l2)
	_set_icon($IconR1, icon_r1)
	_set_icon($IconR2, icon_r2)
	$Art.texture = art
	_apply_tag()
