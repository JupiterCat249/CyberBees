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
## ⭐ 迭代064 UI-11：设计色卡（`电子蜂A5策划案.md`）——亮橙 = 部署费用；深灰 = 蜂王回费量
const COST_COLOR := Color("#FFA300")
const REFUND_COLOR := Color("#5D5D5D")
## ⭐ 迭代064 UI-16：已行动的单位卡做视觉差分（冷灰蓝压暗）
##   ⚠️ 刻意不用 `Color(0.65,0.65,0.65)` —— 那是**手牌"不可用"的中性灰**，语义不同，避免撞色
const ACTED_TINT := Color(0.62, 0.68, 0.78, 1)


func bind(data: Dictionary) -> void:
	unit_id = String(data.get("id", ""))
	## ⭐ 迭代064 UI-11（清单「单位费用颜色不该是白色」）——按设计色卡上色：
	##   · 普通单位：**亮橙 `#FFA300`** ＝ 部署费用
	##   · **蜂王：深灰 `#5D5D5D`** ＝ 每回合回费量
	##     （设计明文：「蜂王单位左上角**不显示部署费用**，取而代之是**灰色的每回合回复费用**」）
	##   原实现一律写白色 `cost`（蜂王 cost = 0 ⇒ 蜂王卡左上角一直显示白色 "0"）⇒ 颜色与数值**两处都不对**。
	var is_queen := String(data.get("type", "unit")) == "queen"
	if is_queen:
		_set_text("CostPlate/Cost", str(data.get("refund", 0)))
		_set_prop("CostPlate/Cost", "theme_override_colors/font_color", REFUND_COLOR)
	else:
		_set_text("CostPlate/Cost", str(data.get("cost", 0)))
		_set_prop("CostPlate/Cost", "theme_override_colors/font_color", COST_COLOR)
	## ⭐ 迭代064 UI-16（清单「双方单位需要有是否行动过的 UI 差分」）：
	##   已行动（a500：使用主动攻击/支援后行动结束）→ 冷灰蓝压暗，一眼看出它本回合已用完。
	modulate = ACTED_TINT if bool(data.get("acted", false)) else Color(1, 1, 1, 1)
	_set_text("Attr_Attack/Value", str(data.get("atk", 0)))
	_set_text("Attr_Health/Value", str(data.get("hp", 0)))
	_set_text("Attr_Speed/Value", str(data.get("move", 0)))
	_set_text("Attr_Range/Value", str(data.get("range", 0)))
	# 阵营色（侧边栏）
	var side_color: Color = SIDE_ALLY if bool(data.get("mine", true)) else SIDE_ENEMY
	_tint("SideLeft", side_color)
	_tint("SideRight", side_color)
	# 卡牌类型底色（本体＝卡面底色）
	_tint("Body", Color(TYPE_COLOR.get(String(data.get("type", "unit")), "#FFFFFF")))
	## ⚠️ 人 2026-10-05 实测"卡面底色依然是默认白色"的**真因（与手牌同源）**：
	##   `Artwork/ArtPlane` 的 stylebox 是不透明色（场景 R3/R4）且铺满卡面
	##   ⇒ 把 `Body` 的类型底色整个盖住 ✗。立绘窗只该做裁剪容器 ⇒ 背景置**全透明**，
	##   让 Body 的类型底色真正透出来 ✓。
	var plane := get_node_or_null("Artwork/ArtPlane") as Panel
	if plane != null:
		var psb := plane.get_theme_stylebox("panel")
		if psb is StyleBoxFlat:
			var psb2: StyleBoxFlat = (psb as StyleBoxFlat).duplicate()
			psb2.bg_color = Color(0, 0, 0, 0)
			plane.add_theme_stylebox_override("panel", psb2)
	## ⚠️ 迭代064 机制-3 曾在此给**立绘框**描一圈 6px 类型色 —— 人 2026-10-05 明确纠正：
	##   类型底色**就该在卡面底色上**（`Body` 本体），**不是刷在边框上**；且当时三个颜色自造有误
	##   （建筑用灰 / 指令用阵营红 / 普通用阵营绿，与策划案 §五 颜色图鉴不符）⇒ **该描边已删除**。
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
## ⭐ 迭代064 B4：**可选/目标标框**（修 P-13 = 清单 UI-17「移动/攻击的可选对象 UI 标记没有看到」）
##
## 为什么必须**画在卡上**：`PITCH = 250` 而单位卡正好 **250×250** ⟹ 卡把它所在格**整片盖住**，
##   规则层给的格子高亮（`board_cell.set_highlight`）在**有单位的格上根本看不见** ——
##   而"攻击/支援目标"恰恰都是有单位的格。故被占格改用**卡上标框**表达（空格仍走格子高亮）。
##
## 实现：懒创建一个 `Panel` 子节点（`z_index = 2` 压在所有卡面内容之上），
##   透明底 + 彩色描边 + 与卡面（圆角 10）贴合的圆角；`kind == ""` 即隐藏。
const MARK_COLOR := {
	"attack": Color("#E8663C"),        ## 可攻击目标（沿用迭代014「减益红橙」）
	"move": Color("#3B816D"),          ## 可移动到位（沿用阵营绿）
	"deploy": Color("#4FB3E8"),        ## 可部署 / 可支援
	"deny": Color(0.6, 0.6, 0.6, 0.85),
	## ⭐ 迭代064 UI-15：**对端选中** —— 紫 `#B070E0`
	##   ⚠️ 选色踩过坑：**先用了纯白 → 打在白色卡面上零对比、截图完全看不见**（读数却一切正常：
	##   Mark 可见、4px、与卡等大）。项目色卡的动作色已被占满（MOVE 绿 / DEPLOY 蓝 /
	##   ATTACK 红橙 / 费用 橙 / 回费 灰），故给"**存在性**"这一类另辟一色（紫），
	##   与四色都拉得开、且在白卡上对比强。
	"remote": Color("#B070E0"),
}


func set_mark(kind: String) -> void:
	var mark := get_node_or_null("Mark") as Panel
	if kind == "" or not MARK_COLOR.has(kind):
		if mark != null:
			mark.visible = false
		return
	if mark == null:
		mark = Panel.new()
		mark.name = "Mark"
		mark.set_anchors_preset(Control.PRESET_FULL_RECT)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.z_index = 2
		add_child(mark)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(4)
	sb.border_color = MARK_COLOR[kind]
	sb.set_corner_radius_all(12)
	mark.add_theme_stylebox_override("panel", sb)
	mark.visible = true


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
