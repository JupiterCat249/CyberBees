extends Control
## HandCard —— 手牌卡控制器（素材场景 card_hand.tscn 的控制脚本）
##
## 结构（素材场景，勿改）：
##   Body(200×200 类型色底) · Artwork/ArtPlane(200×200 clip_contents) · Artwork/Art/Image(立绘)
##   InnerLine(内描边) · BadgeImage(费用徽章) · BadgeImage/Value(费用数字)
##
## 职责（只做三件）：① 数据绑定 ② 头像裁剪重定向 ③ 发交互信号
## **不判断规则**：能否出牌由逻辑层决定，经 set_playable() 下发

signal hand_clicked(card_id: String)
signal hand_long_pressed(card_id: String)

const LONG_PRESS_FRAMES := 30
const ICON_DIR := "res://assets/card_icons/"

var card_data: CardData = null
var _press_frames := 0
var _long_fired := false

@onready var _image: TextureRect = $Artwork/ArtPlane/Image
@onready var _badge_value: Label = $BadgeImage/Value
@onready var _body: Panel = $Body

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	set_meta("image_base_offset", Vector2(_image.offset_left, _image.offset_top))
	set_meta("image_base_scale", _image.scale)

func bind(data: CardData) -> void:
	card_data = data
	if data == null:
		visible = false
		return
	visible = true
	_badge_value.text = str(data.cost) if data.cost >= 0 else "X"
	_apply_type_color(data)
	_apply_artwork(data)
	_apply_crop(data.visual)

func _apply_type_color(data: CardData) -> void:
	var sb: StyleBoxFlat = _body.get_theme_stylebox("panel") as StyleBoxFlat
	if sb == null:
		return
	sb = sb.duplicate()
	sb.bg_color = CardData.type_color_of(data.kind)
	_body.add_theme_stylebox_override("panel", sb)

func _apply_artwork(data: CardData) -> void:
	if data.visual != null and data.visual.artwork != null:
		_image.texture = data.visual.artwork
		return
	var p := ICON_DIR + "icon-" + data.display_name + ".png"
	_image.texture = load(p) if ResourceLoader.exists(p) else null

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

func set_image_offset(new_offset: Vector2, new_scale: Vector2 = Vector2.ZERO) -> void:
	var sz: Vector2 = get_meta("image_base_size", Vector2.ZERO)
	if sz == Vector2.ZERO:
		sz = Vector2(_image.offset_right - _image.offset_left, _image.offset_bottom - _image.offset_top)
		set_meta("image_base_size", sz)
	_image.offset_left = new_offset.x
	_image.offset_top = new_offset.y
	_image.offset_right = new_offset.x + sz.x
	_image.offset_bottom = new_offset.y + sz.y
	if new_scale != Vector2.ZERO:
		_image.scale = new_scale

func set_playable(can_play: bool) -> void:
	modulate = Color(1, 1, 1, 1) if can_play else Color(0.65, 0.65, 0.65, 0.85)

func set_selected(sel: bool) -> void:
	scale = Vector2(1.08, 1.08) if sel else Vector2.ONE
	z_index = 10 if sel else 0

func _gui_input(event: InputEvent) -> void:
	if card_data == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_frames = 0
			_long_fired = false
		elif not _long_fired:
			hand_clicked.emit(card_data.id)

func _process(_delta: float) -> void:
	if card_data == null or _long_fired:
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and get_global_rect().has_point(get_global_mouse_position()):
		_press_frames += 1
		if _press_frames >= LONG_PRESS_FRAMES:
			_long_fired = true
			hand_long_pressed.emit(card_data.id)
	else:
		_press_frames = 0
