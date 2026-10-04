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
##
## ⚠️ 2026-09-19 记录：本文件的 `@tool` 与编辑器守卫曾在提交 b56a2f9 被
##    编辑器内存旧版回写冲掉（159→106 行）—— 已恢复。修改本项目 .gd 一律走 MCP。

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
	## ⚠️ 重置为正常显示 —— 防止烤入场景里遗留的暗色 modulate 让可出的牌也显示为灰
	##   （可出性由 `set_playable()` 控制，不依赖 modulate 历史值）
	modulate = Color(1, 1, 1, 1)
	var bg := _badge()
	if bg != null:
		bg.text = str(data.cost) if data.cost >= 0 else "X"
		## ⭐ 迭代064 UI-11：设计色卡「亮橙 `#FFA300` = 默认部署费用」
		## ⚠️ 人 2026-10-05 明确：手牌费用图标上的**文字应为白色**（此前的黑字判断作废）
		bg.add_theme_color_override("font_color", Color("#FFFFFF"))
	_apply_type_color(data)
	_apply_artwork(data)
	_apply_crop(data.visual)


func _apply_type_color(data: CardData) -> void:
	var body := _body()
	if body == null:
		return
	var tc := CardData.type_color_of(data.kind)
	var sb := body.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		sb = sb.duplicate()
		sb.bg_color = tc
		body.add_theme_stylebox_override("panel", sb)
	## ⭐ 人 2026-10-05 口径：**类型底色直接替换默认白色**（不是"白底上再叠一层"⇒ 避免叠加影响）。
	##   立绘窗 `Artwork/ArtPlane`（场景 `R2`，原本是不透明白 `Color(1,1,1,1)` 且几乎铺满卡面）
	##   ⇒ **直接把它也换成类型底色**（而不是仅置透明），确保**全卡面**都是类型色、没有白底残留 ✓。
	var plane := get_node_or_null("Artwork/ArtPlane") as Panel
	if plane != null:
		var psb := plane.get_theme_stylebox("panel")
		if psb is StyleBoxFlat:
			var psb2: StyleBoxFlat = (psb as StyleBoxFlat).duplicate()
			psb2.bg_color = tc
			plane.add_theme_stylebox_override("panel", psb2)
	_ensure_stripe_overlay()


## ⭐ 迭代064 Stage2（人 2026-10-05）：卡面＝**类型底色 100%** ＋ **白色条纹 10%**
##   条纹＝**原色复用**素材 `assets/ui/fx/crt_scanline_tile.png`（单位卡 `CrtFx` 已在用同一素材）。
##   以 TILE 模式铺满整卡 + `modulate.a = 0.1`（白色条纹 10% 不透明度）。
func _ensure_stripe_overlay() -> void:
	if has_node("TypeStripe"):
		return
	var tex := load("res://assets/ui/fx/crt_scanline_tile.png") as Texture2D
	if tex == null:
		return
	var s := TextureRect.new()
	s.name = "TypeStripe"
	s.texture = tex
	s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	s.stretch_mode = TextureRect.STRETCH_TILE
	s.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	s.modulate = Color(1, 1, 1, 0.1)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## ⭐ 层级（人 2026-10-05 明确）：**类型底色 → 白色条纹 → 单位图像**
	##   `Body` 是类型底色的承载节点（Panel）。Godot 绘制顺序＝"父自身底 → 父的子节点 → 父的后续兄弟"，
	##   故把条纹挂到 `Body` 下，正好得到「底色 → 条纹 → Artwork(单位图像)」✓
	##   （此前挂在卡根且 z_index=1 ⇒ 条纹压在图像之上 ✗，与要求相反）
	var body := _body()
	if body != null:
		body.add_child(s)
	else:
		add_child(s)


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

func set_playable(can_play: bool, dim_black: bool = false) -> void:
	## ⚠️ 迭代064 批次 B3（人 2026-09-27 问题清单 UI-9 / UI-12）：
	##   **灰化只压 RGB，绝不压 alpha**。原实现是 `Color(0.65,0.65,0.65,0.85)` ——
	##   那个 0.85 会经 `modulate` **级联到全部子节点**，把**费用图标与费用数字也一并变成半透明**
	##   （人明确：「费用标记不应该在任何情况下变半透明」「不可选时应该是整体变灰，
	##     而不是变灰的同时费用图标和费用数字（甚至卡面本身）变半透明」）。
	##   现在：整卡统一变灰（RGB × 0.65），费用标记保持**完全不透明**。
	## ⭐ 迭代064 UI-21：`dim_black` = **非本方**手牌 → 直接变黑（0.22）；本方"不可用" → 中性灰（0.65）。
	##   两者都**只压 RGB、不压 alpha**（守 UI-9 / UI-12 口径）。
	if can_play:
		modulate = Color(1, 1, 1, 1)
	elif dim_black:
		modulate = Color(0.22, 0.22, 0.22, 1)
	else:
		modulate = Color(0.65, 0.65, 0.65, 1)


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
