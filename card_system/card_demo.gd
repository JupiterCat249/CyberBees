@tool
extends Node2D
## ============================================================
## 批量渲染示例：一个数据数组 → 批量实例化 shader 卡牌
## @tool：在 Godot 编辑器里打开 card_demo.tscn 即可直接看到全部卡牌
## 实际项目中把 DATA 换成 JSON / CSV / 数据库读取即可
## 图标：0攻击 1速度 2血量 3射程 4兵蜂 5建筑 6指令 7蜂王（-1 不显示）
## ============================================================

const CARD := preload("res://card_system/card_auto.tscn")
const ART_DIR := "res://card_system/art/"

## 立绘填文件名（不含扩展名），数字 -1 = 不显示
## cost=费用 l1/l2=左栏上下数值 r1/r2=右栏上下数值 i*=对应图标
const DATA := [
	# ---------- 截图复刻：巡航导弹（右栏：盾图标无数值 + 射程3 + 准星） ----------
	{"art": "卡牌d1-巡航导弹", "cost": 6, "tag": 6, "l1": 5, "li1": 0, "li2": 1, "r1": -1, "ri1": 2, "r2": 3, "ri2": 3},
	# ---------- 蜂王 / 兵种（r1=血量，配盾图标 ri1=2） ----------
	{"art": "卡牌a-金刚蜂王", "cost": 8, "tag": 7, "l1": 7, "li1": 0, "li2": 1, "r1": 8, "ri1": 2, "r2": 2, "ri2": 3},
	{"art": "卡牌c1-叶蜂", "cost": 2, "tag": 4, "l1": 2, "li1": 0, "li2": 1, "r1": 3, "ri1": 2, "r2": 1, "ri2": 3},
	{"art": "卡牌c1-泥蜂", "cost": 2, "tag": 4, "l1": 3, "li1": 0, "li2": 1, "r1": 4, "ri1": 2, "r2": 2, "ri2": 3},
	{"art": "卡牌c2-熊蜂", "cost": 5, "tag": 4, "l1": 5, "li1": 0, "li2": 1, "r1": 8, "ri1": 2, "r2": -1, "ri2": 3},
	# ---------- 建筑（血量高、射程近） ----------
	{"art": "卡牌b1-蜂巢", "cost": 4, "tag": 5, "l1": -1, "li1": -1, "li2": -1, "r1": 5, "ri1": 2, "r2": -1, "ri2": -1},
	{"art": "卡牌b1-蜂巢III", "cost": 9, "tag": 5, "l1": -1, "li1": -1, "li2": -1, "r1": 12, "ri1": 2, "r2": -1, "ri2": -1},
	# ---------- 指令（无血量/攻击单位属性，只显示费用与类别） ----------
	{"art": "卡牌d1-电击", "cost": 3, "tag": 6, "l1": 4, "li1": 0, "li2": -1, "r1": -1, "ri1": -1, "r2": -1, "ri2": -1},
	{"art": "卡牌d1-电击III", "cost": 7, "tag": 6, "l1": 9, "li1": 0, "li2": -1, "r1": -1, "ri1": -1, "r2": -1, "ri2": -1},
	{"art": "卡牌d2-治疗", "cost": 3, "tag": 6, "l1": 4, "li1": 2, "li2": -1, "r1": -1, "ri1": -1, "r2": -1, "ri2": -1},
]

const COLS := 4
const GAP := 250.0          # 地图格 250x250 紧邻铺满，无间隙
const CARD_COUNT := 16      # 4x4 = 16 张正好填满 1000x1000 地图本体
## 地图本体在 1920x1080 设计坐标系中的位置（完全居中：1008 含描边，本体 1000）
const MAP_ORIGIN := Vector2(460.0, 40.0)
const DESIGN := Vector2(1920.0, 1080.0)
## 生成的卡牌节点名前缀（重建时用于清理，避免编辑器热重载后重复）
const GEN_PREFIX := "GenCard_"

var _holder: Node2D
var _snapping := false


func _ready() -> void:
	# 编辑器里只构建展示，不执行截图钩子
	if Engine.is_editor_hint():
		_build_cards()
		return

	# 运行时：窗口尺寸变化 → 重新等比适配；OS 窗口吸附 16:9
	get_window().size_changed.connect(_update_fit)
	get_window().size_changed.connect(_snap_window_aspect)

	# 验证用：设置环境变量 CARD_SHOT=输出路径 时，定窗口尺寸后构建并截图退出
	# 可选 CARD_W / CARD_H 覆盖窗口尺寸（默认 1920x1080），用于验证小窗口自适应
	var shot := OS.get_environment("CARD_SHOT")
	if shot != "":
		var w := 1920
		var h := 1080
		var ew := OS.get_environment("CARD_W")
		var eh := OS.get_environment("CARD_H")
		if ew != "":
			w = ew.to_int()
		if eh != "":
			h = eh.to_int()
		# 关闭拉伸，1 设计像素 = 1 屏幕像素，截图便于逐像素验证
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		get_window().size = Vector2i(w, h)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		_build_cards()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot)
		get_tree().quit()
	else:
		_build_cards()


## 根据 DATA 批量实例化卡牌（编辑器与运行时都会调用）
func _build_cards() -> void:
	# 先清掉上一次生成的节点（编辑器中脚本热重载 / 场景重新打开时防重复）
	for c in get_children():
		if c.name.begins_with(GEN_PREFIX):
			remove_child(c)
			c.free()

	# 卡牌容器：整体缩放居中——任何窗口（编辑器内嵌预览 / 全屏 / 独立窗口）
	# 卡牌都完整可见、比例不变（最大 1.0 = 250px 设计尺寸，只缩小不放大）
	_holder = Node2D.new()
	var holder: Node2D = _holder
	holder.name = GEN_PREFIX + "holder"
	add_child(holder)

	for i in CARD_COUNT:
		var d: Dictionary = DATA[i % DATA.size()]  # 不足 16 张时循环复用
		var c := CARD.instantiate()
		c.name = GEN_PREFIX + str(i)
		@warning_ignore("integer_division")
		c.position = MAP_ORIGIN + Vector2((i % COLS) * GAP, (i / COLS) * GAP)
		holder.add_child(c)
		c.set("art", load(ART_DIR + d["art"] + ".png"))
		c.set("cost", d["cost"])
		c.set("icon_tag", d["tag"])
		c.set("stat_l1", d["l1"])
		c.set("icon_l1", d["li1"])
		c.set("icon_l2", d["li2"])
		c.set("stat_r1", d["r1"])
		c.set("icon_r1", d["ri1"])
		c.set("stat_r2", d["r2"])
		c.set("icon_r2", d["ri2"])

	_update_fit()


## 按 1920x1080 设计坐标系等比适配视口（与 battle_ui 同一系数，
## 卡牌网格永远精确覆盖居中地图本体的位置）
func _update_fit() -> void:
	if _holder == null:
		return
	var vs := get_viewport_rect().size
	var s: float = minf(vs.x / DESIGN.x, vs.y / DESIGN.y)
	_holder.scale = Vector2(s, s)
	_holder.position = (vs - DESIGN * s) * 0.5


## OS 窗口尺寸吸附到最近 16:9（编辑器内嵌面板不应用拉伸，跳过）
func _snap_window_aspect() -> void:
	if _snapping:
		return
	var w := get_window()
	if w.mode != Window.MODE_WINDOWED:
		return
	# 内嵌游戏面板：窗口尺寸 == 画布视口尺寸（不应用拉伸），不干预
	if Vector2(w.size) == get_viewport_rect().size:
		return
	var k: float = minf(w.size.x / 16.0, w.size.y / 9.0)
	var target := Vector2i(int(16.0 * k), int(9.0 * k))
	if absi(target.x - w.size.x) <= 1 and absi(target.y - w.size.y) <= 1:
		return
	_snapping = true
	w.size = target
	_snapping = false
