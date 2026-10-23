extends RefCounted
## 预览渲染（自 arena_view 切出 —— 迭代085 · B5 第八刀）
##
## 判据：**只读 PreviewData 资源**并把高亮/标框打到既有节点上，不重算规则、不改布局数值。
##   视图看到的一切都来自规则层算好的 `PreviewData`（与试算同源）—— 这条口径不要在这里破坏。

const PreviewKind := preload("res://src/battle/preview_kind.gd")
const Fx := preload("res://src/view/view_fx.gd")
## 预览后果浮字颜色＝伤害红（与 arena_view.COL_DAMAGE 同色；0.9 透明度＝提示而非结算）
const HINT_COLOR := Color(1.0, 0.125, 0.0, 0.9)
## 反击浮字色（橙黄；与伤害红区分。批2 迁入 FxParams 资源）
const HINT_COLOR_INCOMING := Color(1.0, 0.62, 0.12, 0.9)

## `fx` = FxParams 资源（可空；空则用资源化前的默认值）—— 迭代145
static func render(cells: Dictionary, unit_nodes: Dictionary, preview: Resource,
		engine, find_unit: Callable, fx_root: Control = null,
		float_scene: PackedScene = null, fx = null) -> void:
	## ⭐ 迭代064 UI-15：先把**对端选中**的格子记下来 —— 下面会清空所有格子的 selected，
	##   而对端选中**不属于预览**、不能被预览清掉（否则对手选中会一帧就被自己的预览刷没）。
	## ⭐ 迭代093（人 2026-10-23）：后果浮字**每次重算先清**（与下面标框同一套"先清再画"口径）
	if fx_root != null:
		for ch in fx_root.get_children():
			if ch.has_meta("preview_hint"):
				ch.queue_free()
	var rsel := Vector2i(-1, -1)
	for c in cells.keys():
		if cells[c].selected:
			rsel = c
			break
	for c in cells.keys():
		cells[c].set_highlight("")
		cells[c].set_selected(false)
	## ⚠️ 卡上"标框"必须**每次先清**再按新预览重打 —— 否则预览消失（取消选中/操作结束）后标框残留。
	##   （迭代064 B4 实测踩到：只在 `preview != null` 分支里打标、却没在开头清 → 清空后红框不退。）
	for k in unit_nodes.keys():
		var un = unit_nodes[k]
		if un != null and is_instance_valid(un) and un.has_method("set_mark"):
			## ⭐ 迭代064 UI-15：清标框时**顺带**把"对端选中"打在对应卡上。
			##   为什么必须打在卡上：单位卡正好 250×250（＝`PITCH`）会把**格子填充整片盖住** ——
			##   实测截图中"对手选中"在有单位的格上完全看不见（与 P-13 同一类坑）。
			##   为什么在**这里**打：放函数末尾会被上面的 `preview == null: return` 跳过；
			##   放在预览打标之前则会被 preview 覆盖 —— 本循环是唯一"既清又打、且不会被跳过"的位置。
			##   （若该单位同时是我方预览的可攻击目标，预览的红橙标框会覆盖它 —— 可接受：攻击提示优先）
			var mark_kind := ""
			if rsel.x >= 0:
				var iu = find_unit.call(String(k))
				if iu != null and iu.cell == rsel:
					mark_kind = "remote"
			un.set_mark(mark_kind)
	## ⭐ 迭代064 UI-15：重打对端选中标记（与本地预览互不干扰）
	if rsel.x >= 0 and cells.has(rsel):
		cells[rsel].set_selected(true)
	var style := {
		PreviewKind.Kind.DEPLOY: "deploy",
		PreviewKind.Kind.MOVE: "move",
		PreviewKind.Kind.ATTACK: "attack",
		PreviewKind.Kind.COMMAND: "attack",
		PreviewKind.Kind.SUPPORT: "deploy",
	}
	## ⭐ 迭代064 B4（修 P-13 = 清单 UI-17）：**被占格的标记改画在"卡上"**
	##   原因：`PITCH = 250` 而单位卡正好 250×250 → 卡把自己那格**整片盖住**，
	##   格上的高亮在"有单位"的格上根本看不见，而攻击/支援目标恰恰都是有单位的格。
	##   这里按 `PreviewData.units`（受影响单位，见 `preview_data.gd:38`）给对应卡片打标；
	##   `kind → 样式` 复用下面同一张 `style` 映射表，**视图不额外判断规则**。
	if preview == null:
		return
	var mark_kind := String(style.get(preview.kind, ""))
	for pc in preview.cells:
		if cells.has(pc.cell):
			cells[pc.cell].set_highlight(String(style.get(pc.kind, "")))
	## ⚠️ 人 2026-10-05：「在敌方单位上套红框（这个不需要额外显示）」 ✗
	##   AOE 指令卡要的是**效果范围**（格高亮），不是逐单位红框 ⇒ 选中的是 AOE 卡时**跳过单位打标**。
	var skip_unit_marks := false
	if engine != null and int(engine.sel_kind) == 1:
		var hc: CardData = null
		var hh: Array = engine.state.sides[engine.state.active]["hand"]
		if engine.sel_hand_index >= 0 and engine.sel_hand_index < hh.size():
			hc = hh[engine.sel_hand_index]
		if hc is CommandData and (hc as CommandData).aoe_span > 0:
			skip_unit_marks = true
	## ⭐ 迭代064 遗留①（**人 2026-10-05 口径：这一条是「应该」**）：远端预览**不再跳过单位打标** ——
	##   「敌方**应该**能够看到我方选中单位进入攻击状态后的攻击范围以及**选择的攻击目标**」——
	##   联机信息完全透明的主动设计 ⇒ 对端视图与本地视图渲染同一份 PreviewData（含目标标框）。
	##   旧条件里的 `not _preview_is_remote` 据人口径作废；"选指令卡时给对手单位套红框"仍由上面的
	##   AOE 跳过覆盖（那才是当时真正要挡的现象）。
	if not skip_unit_marks:
		for u in preview.units:
			var un = unit_nodes.get(u.instance_id, null)
			if un != null and is_instance_valid(un) and un.has_method("set_mark"):
				un.set_mark(mark_kind)
	## ⭐ 迭代093（人 2026-10-23「攻击类操作的**后果预览浮字不存在**」）：
	##   把规则层算好的后果（PreviewData.hints：打多少 / 是否击杀）摆到对应单位卡上方。
	##   常驻不播动画（`浮字上浮` 会淡出并 queue_free）；预览一变就整体重画 ⇒ 不会残留旧数字。
	if fx_root != null and float_scene != null and not preview.hints.is_empty():
		for id in preview.hints.keys():
			var card = unit_nodes.get(id, null)
			if card == null or not is_instance_valid(card):
				continue
			var info: Dictionary = preview.hints[id]
			if info.has("incoming"):
				## 我方卡：**被反击**的预计数值（人 2026-10-23：无反击显示 0，不隐藏）
				var inc: int = int(info.get("incoming", 0))
				var itxt := "反击 0" if inc <= 0 else "反击 -%d" % inc
				if inc > 0 and bool(info.get("incoming_lethal", false)):
					itxt = "反击 -%d 阵亡" % inc
				var c_in: Color = fx.preview_hint_counter_color if fx != null else HINT_COLOR_INCOMING
				Fx.preview_hint(fx_root, float_scene, card, itxt, c_in, fx)
				continue
			var dmg: int = int(info.get("dmg", 0))
			var txt := "-%d" % dmg
			if bool(info.get("blocked", false)):
				txt = "抵挡"          ## 装甲/护盾/力场：完全免伤，写 "-0" 会误导
			elif bool(info.get("lethal", false)):
				txt = "-%d 击杀" % dmg
			var c_dmg: Color = fx.preview_hint_damage_color if fx != null else HINT_COLOR
			Fx.preview_hint(fx_root, float_scene, card, txt, c_dmg, fx)
