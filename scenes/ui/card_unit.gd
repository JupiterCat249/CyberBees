extends Control
## UnitCard —— 地图单位卡控制器（素材场景 card_unit.tscn 的控制脚本）
##
## 结构（素材场景，勿改）：Body · SideLeft/Right · CostPlate/Cost · UnitType/TextureRect
##   Artwork/ArtPlane(立绘，内含 crt 特效) · Attr_Attack / Attr_Health / Attr_Speed / Attr_Range(四维：ValueCell/Value + AttrCell/Icon) · InnerLine
##
## 职责：① 绑 UnitInstance（静态走 data、运行态走实例） ② 发交互信号
## **不判断规则**：可选中/可行动由逻辑层下发

signal unit_clicked(instance_id: String)
signal unit_long_pressed(instance_id: String)

const LONG_PRESS_FRAMES := 30

var inst: UnitInstance = null
var _press_frames := 0
var _long_fired := false

## 惰性取节点（理由同 card_hand.gd：bind() 可能早于 @onready 赋值）
func _body() -> Panel: return $Body
func _side_l() -> Panel: return $SideLeft
func _side_r() -> Panel: return $SideRight
func _cost() -> Label: return $CostPlate/Cost
func _art() -> Panel: return $Artwork/ArtPlane

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

## 绑定运行态实例（取值一律走实例 / 实例的 data）
func bind(p_inst: UnitInstance) -> void:
	inst = p_inst
	if inst == null:
		visible = false
		return
	visible = true
	var d := inst.data
	# 蜂王/资源建筑显示「每回合回费」，其余显示部署费（A5 口径）
	_cost().text = str(d.refund) if d.refund > 0 else str(d.cost)
	_apply_faction(inst.side)
	_apply_type_color(d.kind)
	if d.visual != null and d.visual.artwork != null:
		_art().add_theme_stylebox_override("panel", _art_style(d.visual.artwork))
	refresh_stats()
	if not inst.hp_changed.is_connected(_on_inst_changed):
		inst.hp_changed.connect(_on_inst_changed)
		inst.effects_changed.connect(_on_inst_changed_nop)

func _on_inst_changed(_i: UnitInstance, _o: int, _n: int) -> void:
	refresh_stats()

func _on_inst_changed_nop(_i: UnitInstance) -> void:
	refresh_stats()

## 刷新四维
func refresh_stats() -> void:
	if inst == null:
		return
	$Attr_Attack/Value.text = str(inst.atk())
	$Attr_Health/Value.text = str(inst.current_hp)
	$Attr_Speed/Value.text = str(inst.move_range())
	$Attr_Range/Value.text = str(inst.attack_range())

## 阵营色（D3）
func _apply_faction(side: int) -> void:
	var col := CardData.faction_color_of(side)
	for p in [_side_l(), _side_r()]:
		var sb: StyleBoxFlat = p.get_theme_stylebox("panel") as StyleBoxFlat
		if sb != null:
			sb = sb.duplicate()
			sb.bg_color = col
			p.add_theme_stylebox_override("panel", sb)

## 类型色（D4）
func _apply_type_color(k: CardData.CardKind) -> void:
	var sb: StyleBoxFlat = _body().get_theme_stylebox("panel") as StyleBoxFlat
	if sb == null:
		return
	sb = sb.duplicate()
	sb.bg_color = CardData.type_color_of(k)
	_body().add_theme_stylebox_override("panel", sb)

func _art_style(tex: Texture2D) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 1)
	sb.texture = tex
	return sb

func set_selectable(v: bool) -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if v else Control.CURSOR_ARROW
	modulate = Color(1, 1, 1, 1) if v else Color(0.8, 0.8, 0.8, 0.9)

func set_selected(sel: bool) -> void:
	z_index = 20 if sel else 0

func _gui_input(event: InputEvent) -> void:
	if inst == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_frames = 0
			_long_fired = false
		elif not _long_fired:
			unit_clicked.emit(inst.instance_id)

func _process(_delta: float) -> void:
	if inst == null or _long_fired:
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and get_global_rect().has_point(get_global_mouse_position()):
		_press_frames += 1
		if _press_frames >= LONG_PRESS_FRAMES:
			_long_fired = true
			unit_long_pressed.emit(inst.instance_id)
	else:
		_press_frames = 0
