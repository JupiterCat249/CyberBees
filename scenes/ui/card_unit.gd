@tool
extends Control
## 地图单位卡（250×250）：节点负责外观，脚本只做**数据绑定**与点击信号
##
## `@tool` = 在**编辑器里**也能绑定内容 → 打开战斗场景即可直接看到卡面（不必运行）
##
## ⚠️ 节点路径以 **card_unit.tscn 的真实层级**为准：
##    · 费用 = CostPlate/Cost
##    · 四维 = Attr_Attack / Attr_Health / Attr_Speed / Attr_Range 下的 Value
##    · **立绘 = Artwork/ArtPlane/TextureRect**（此前漏绑 → 单位放出后立绘永远是默认图）
##    统一用 _set_prop(path, prop, value) 取节点并**判空**，缺节点只跳过、不崩。
##
## 绑定数据（视觉层字典，不含规则判断）：
##   id / cost / atk / hp / move / range / mine / type / art(Texture2D)
##   mine = true → 我方绿(#3B816D) / false → 敌方红(#A84331)（策划案 §五 卡牌侧边）
##   type → 卡牌类型底色：unit #FFFFFF / queen #FFD07E / building #DDC29B / order #D9D9D9

signal unit_pressed(unit_id: String)

const SIDE_ALLY := Color("#3B816D")
const SIDE_ENEMY := Color("#A84331")
const TYPE_COLOR := {
	"unit": "#FFFFFF", "queen": "#FFD07E", "building": "#DDC29B", "order": "#D9D9D9",
}
## 类型图标（`UnitType/TextureRect`）—— 单位类型 → **生产素材**路径
## 2026-09-24：素材从 `archive/legacy/card-system/card_system/icons/` **迁出**到 `assets/type_icons/`
## （此前场景里烤的是 `archive/legacy/.../soldier.png`，且写死不随单位类型变）。
const TYPE_ICON := {
	"unit": "res://assets/type_icons/soldier.png",
	"queen": "res://assets/type_icons/queen.png",
	"building": "res://assets/type_icons/building.png",
	"order": "res://assets/type_icons/command.png",
}
## 效果徽标边长（`UnitEffects` 容器 158×40 → 4 个 36px + 默认间隔刚好放得下）
const EFFECT_BADGE_SIZE := 36.0
## ⚠️ 2026-09-24 人实机反馈修正：**徽标不加任何底衬 / 描边 / 内缩**。
##    曾用「`corner_radius = 18` 的圆形 Panel 底衬 + 四周 3px 内缩」，人实机看到的观感是
##    「圆球状外圈 + 原图被裁小 + 多占一圈空间」——已移除。
##    现在图标**满幅**画在自己那一格里：不裁剪、不多占空间；可读性靠
##    ① 满幅（比内缩版大 ~20%）② 悬停提示（tooltip 带效果名与剩余回合）
##    ③ 若日后仍嫌浅色卡面上偏淡，再考虑"与格子等大的**方形**底色"（同样零内缩、零额外空间）。
## 图标缓存（路径 → Texture2D；值为 null 表示"已查过但没有"）
static var _icon_cache: Dictionary = {}

var unit_id := ""


## ⚠️ 每次绑定都**重置为正常显示** ——
##   否则烤入场景里遗留的暗色 modulate（历史运行时状态）会让可出的牌也显示为灰。
##   可出性由 `set_playable()` 单独控制，不依赖 modulate 的历史值。
func bind(data: Dictionary) -> void:
	unit_id = String(data.get("id", ""))
	modulate = Color(1, 1, 1, 1)
	_set_text("CostPlate/Cost", str(data.get("cost", 0)))
	_set_text("Attr_Attack/Value", str(data.get("atk", 0)))
	_set_text("Attr_Health/Value", str(data.get("hp", 0)))
	_set_text("Attr_Speed/Value", str(data.get("move", 0)))
	_set_text("Attr_Range/Value", str(data.get("range", 0)))
	# 阵营色（侧边栏）
	var side_color: Color = SIDE_ALLY if bool(data.get("mine", true)) else SIDE_ENEMY
	_tint("SideLeft", side_color)
	_tint("SideRight", side_color)
	# 卡牌类型底色（本体）
	_tint("Body", Color(TYPE_COLOR.get(String(data.get("type", "unit")), "#FFFFFF")))
	# **立绘同步**：按实际卡数据的立绘刷新
	var tex = data.get("art", null)
	if tex is Texture2D:
		_set_prop("Artwork/ArtPlane/TextureRect", "texture", tex)
	# **类型图标**：按单位类型切换（unit / queen / building / order）
	_bind_type_icon(String(data.get("type", "unit")))
	# **持有效果**：卡面小图标条（数据由 `arena_view._effect_badges()` 装配）
	_bind_effects(data.get("effects", []))


## 类型图标：按单位类型切换；无素材则**整块隐藏**（不留上一张的残影）
func _bind_type_icon(kind: String) -> void:
	var tex: Texture2D = _icon(String(TYPE_ICON.get(kind, TYPE_ICON["unit"])))
	_set_prop("UnitType/TextureRect", "texture", tex)
	_set_prop("UnitType", "visible", tex != null)


## 持有效果徽标：按 items 数量增删 `UnitEffects` 子节点（HBoxContainer 负责排布）
## items = [{name, icon, debuff, turns}, …]（装配见 `arena_view._effect_badges()`）
## 说明：**只渲染传入的效果列表**（运行态效果）；卡牌自带被动在 `UnitData.passives`，不会出现在这里。
func _bind_effects(items) -> void:
	var box := get_node_or_null("UnitEffects")
	if box == null:
		return
	var list: Array = items if items is Array else []
	## 多退：从尾部删（复用已有节点，避免每次刷新整条重建）
	while box.get_child_count() > list.size():
		var extra := box.get_child(box.get_child_count() - 1)
		box.remove_child(extra)
		extra.queue_free()
	## 少补
	while box.get_child_count() < list.size():
		box.add_child(_make_badge())
	## 逐个填内容（**裸图标**：直接满幅挂上去，不做任何裁剪/内缩/底衬）
	for i in list.size():
		var badge := box.get_child(i) as TextureRect
		if badge == null:
			continue
		var d: Dictionary = list[i]
		var tex: Texture2D = d.get("icon", null)
		badge.texture = tex
		badge.visible = tex != null
		badge.tooltip_text = _effect_tooltip(d)


## 徽标节点：**裸图标满幅**（无底衬 / 无描边 / 无内缩）
## ⚠️ 2026-09-24 人实机反馈：原先「圆形 `Panel` 底衬（`corner_radius = 18`）+ 四周 3px 内缩」的观感是
##    "圆球状外圈 + 原图被裁小 + 多占一圈空间" → 已移除，改为直接把图标画满自己那一格。
## ⚠️ 局部名**不能叫 `tr`** —— 会触发 SHADOWED_VARIABLE_BASE_CLASS（`Object.tr()` 翻译方法），实测踩到
func _make_badge() -> TextureRect:
	var badge := TextureRect.new()
	badge.name = "EffectBadge"
	badge.custom_minimum_size = Vector2(EFFECT_BADGE_SIZE, EFFECT_BADGE_SIZE)
	## 容器高 40 > 徽标 36：竖向**居中不拉伸**，保持正方形（按比例居中，不裁剪原图）
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return badge


## 悬停提示：「装甲」/「灼烧 · 剩余 2 回合」（`turns < 0` = 永久，不显示回合）
func _effect_tooltip(d: Dictionary) -> String:
	var nm := String(d.get("name", ""))
	if nm == "":
		return ""
	var turns := int(d.get("turns", -1))
	return nm if turns < 0 else "%s · 剩余 %d 回合" % [nm, turns]


## 图标：按路径加载并缓存（避免每次刷新重复 load）
func _icon(path: String) -> Texture2D:
	if path == "":
		return null
	if _icon_cache.has(path):
		return _icon_cache[path] as Texture2D
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_icon_cache[path] = tex
	return tex


## 设节点属性（缺节点则跳过，不崩）
func _set_prop(path: String, prop: String, value) -> void:
	var node := get_node_or_null(path)
	if node != null:
		node.set(prop, value)


func _set_text(path: String, value: String) -> void:
	_set_prop(path, "text", value)


## 视角换色（迭代062）：seat≠0 的玩家也应看到「自己=绿方」→ 只改两侧配色，不动任何数据
func set_mine(m: bool) -> void:
	_tint("SideLeft", SIDE_ALLY if m else SIDE_ENEMY)
	_tint("SideRight", SIDE_ALLY if m else SIDE_ENEMY)


## 给 Panel 换底色（复制 StyleBoxFlat，避免改到共享资源）
func _tint(path: String, color: Color) -> void:
	var node := get_node_or_null(path) as Control
	if node == null:
		return
	var sb := node.get_theme_stylebox("panel") as StyleBoxFlat
	if sb == null:
		return
	sb = sb.duplicate()
	sb.bg_color = color
	node.add_theme_stylebox_override("panel", sb)


func _gui_input(event: InputEvent) -> void:
	# 编辑器里不响应点击（避免误操作）
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		unit_pressed.emit(unit_id)
