extends RefCounted
## 预览渲染（自 arena_view 切出 —— 迭代085 · B5 第八刀）
##
## 判据：**只读 PreviewData 资源**并把高亮/标框打到既有节点上，不重算规则、不改布局数值。
##   视图看到的一切都来自规则层算好的 `PreviewData`（与试算同源）—— 这条口径不要在这里破坏。

const PreviewKind := preload("res://scripts/battle/preview_kind.gd")

static func render(cells: Dictionary, unit_nodes: Dictionary, preview: Resource,
		engine, find_unit: Callable) -> void:
	## ⭐ 迭代064 UI-15：先把**对端选中**的格子记下来 —— 下面会清空所有格子的 selected，
	##   而对端选中**不属于预览**、不能被预览清掉（否则对手选中会一帧就被自己的预览刷没）。
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
