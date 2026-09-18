@tool
extends Control
## HandCard —— 手牌卡控制器（素材场景 card_hand.tscn）
##
## `@tool` = 在**编辑器里**也能绑定内容 → 打开战斗场景即可直接看到手牌（不必运行）
##
## 结构（勿改）：Body(200×200 类型色底) · Artwork/ArtPlane(200×200 clip_contents) · ArtPlane/Image(立绘)
##                InnerLine(内描边) · BadgeImage/Value(费用数字)
##
## 职责：① 数据绑定 ② 头像裁剪重定向 ③ 发交互信号
## **不判断规则**：能否出牌由逻辑层决定，经 set_playable() 下发
##
## 说明：一律用 `get_node_or_null` 取节点并判空 —— 既避免"缺节点即崩"，
##       也避免 `@onready` 的赋值时机问题（父节点 add_child() 会同步触发 bind()）。

signal hand_clicked(card_id: String)
signal hand_long_pressed(card_id: String)

const LONG_PRESS_FRAMES := 30
const ICON_DIR := "res://assets/card_icons/"

var card_data: CardData = null
var _press_frames := 0
var _long_fired := false


# ---------------- 节点取用（判空） ----------------

func _img() -> TextureRect:
	return get_node_or_null("Artwork/ArtPlane/Image") as TextureRect

func _badge() -> Label:
	return get_node_or_null("BadgeImage/Value") as Label

func _body() -> Panel:
	return get_node_or_null("Body") as Panel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var im := _img()
	if im != null:
		set_meta("image_base_offset", Vector2(im.offset_left, im.offset_top))
		set_meta("image_base_scale", im.scale)


# ---------------- ① 数据绑定 ----------------

func bind(data: CardData) -> void:
	card_data = data
	if data == null:
		visible = false
		return
	visible = true
	var bg := _badge()
	if bg != null:
		bg.text = str(data.cost) if data.cost >= 0 else "X"
	_apply_type_color(data)
	_apply_artwork(data)
	_apply_crop(data.visual)


func _apply_type_color(data: CardData) -> void:
	var body := _body()
	if body == null:
		return
	var sb := body.get_theme_stylebox("panel") as StyleBoxFlat
	if sb == null:
		return
	sb = sb.duplicate()
	sb.bg_color = CardData.type_color_of(data.kind)
	body.add_theme_stylebox_override("panel", sb)


func _apply_artwork(data: CardData) -> void:
	var im := _img()
	if im == null:
		return
	if data.visual != null and data.visual.artwork != null:
		im.texture = data.visual.artwork
		return
	var p := ICON_DIR + "icon-" + data.display_name + ".png"
	im.texture = load(p) if ResourceLoader.exists(p) else null


# ---------------- ② 头像裁剪重定向 ----------------
## 手牌用**立绘 + 定向裁剪**做头像：立绘(Image)大于裁剪窗(ArtPlane)，
## 靠调整 Image 在裁剪窗内的相对位置，决定窗口里显示立绘的哪一块。
## crop_offset = 在素材基准位置上的**增量**（像素）。

func _apply_crop(vis: CardVisual) -> void:
	var base: Vector2 = get_meta("image_base_offset", Vector2.ZERO)
	var base_scale: Vector2 = get_meta("image_base_scale", Vector2.ONE)
	var off := base
	var scl := base_scale
	if vis != null:
		off = base + vis.crop_offset
		if vis.crop_scale > 0.0:
			scl = Vector2(vis.crop_scale, vis.crop_scale)
	set_image_offset(off, scl)


## 直接重定向立绘位置（供外部/编辑器调试；不走 CardVisual 时用它）
func set_image_offset(new_offset: Vector2, new_scale: Vector2 = Vector2.ZERO) -> void:
	var im := _img()
	if im == null:
		return
	var sz: Vector2 = get_meta("image_base_size", Vector2.ZERO)
	if sz == Vector2.ZERO:
		sz = Vector2(im.offset_right - im.offset_left, im.offset_bottom - im.offset_top)
		set_meta("image_base_size", sz)
	im.offset_left = new_offset.x
	im.offset_top = new_offset.y
	im.offset_right = new_offset.x + sz.x
	im.offset_bottom = new_offset.y + sz.y
	if new_scale != Vector2.ZERO:
		im.scale = new_scale


# ---------------- ③ 可出牌态（逻辑层下发，视图只表现） ----------------

func set_playable(can_play: bool) -> void:
	modulate = Color(1, 1, 1, 1) if can_play else Color(0.65, 0.65, 0.65, 0.85)


func set_selected(sel: bool) -> void:
	scale = Vector2(1.08, 1.08) if sel else Vector2.ONE
	z_index = 10 if sel else 0


# ---------------- 输入 → 信号 ----------------

func _gui_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return                      # 编辑器里不响应点击（避免误操作）
	if card_data == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_frames = 0
			_long_fired = false
		elif not _long_fired:
			hand_clicked.emit(card_data.id)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():     # 编辑器里不跑输入逻辑
		return
	if card_data == null or _long_fired:
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
			and get_global_rect().has_point(get_global_mouse_position()):
		_press_frames += 1
		if _press_frames >= LONG_PRESS_FRAMES:
			_long_fired = true
			hand_long_pressed.emit(card_data.id)
	else:
		_press_frames = 0
