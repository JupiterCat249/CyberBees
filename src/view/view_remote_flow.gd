extends RefCounted
## 远端呈现的**纯查询**（自 arena_view._on_remote_select / _on_remote_action 切出 —— 迭代110）
##
## 判据：只回答"该给哪份远端预览"，**不碰节点、不改选中、不渲染**。
##   格子白框 / 预览绘制 / 手牌标记仍由视图与 view_preview / view_remote_marks 负责。
##
## ⚠️ 行为契约（与切分前逐分支一致）：
##   · 只有"对端（side != my_seat）选中了**对端自己的单位**"才给预览；其余一律空；
##   · 指令卡：文本形如 "选中手牌 <卡名>"，且该卡确实在对端手里 ⇒ 才算效果范围；
##     名字对不上时**什么都不做**（不 bind 也不 clear —— 保留切分前的原行为）。


## 远端单位预览：返回 {unit, preview}（任一可为 null）
static func remote_unit_preview(engine, my_seat: int, side: int, cell: Vector2i) -> Dictionary:
	if side == my_seat or engine == null or engine.state == null or int(cell.x) < 0:
		return {"unit": null, "preview": null}
	var ru: UnitInstance = engine.state.board.unit_at(cell)
	if ru == null or int(ru.side) == my_seat:
		return {"unit": null, "preview": null}
	return {"unit": ru, "preview": engine.remote_preview_of(ru)}


## 对端指令卡的效果范围预览：文本 "选中手牌 <卡名>" + 待确认中心格
##   找不到同名卡时返回 null（视图据此保持原状，与控制流一致）
static func remote_command_preview(engine, side: int, text: String, cell: Vector2i) -> Resource:
	if engine == null or engine.state == null:
		return null
	if not String(text).begins_with("选中手牌 "):
		return null
	var nm := String(text).replace("选中手牌 ", "")
	var hh: Array = engine.state.sides[side]["hand"]
	for i in hh.size():
		if String(hh[i].display_name) == nm:
			return engine.remote_command_preview(i, cell)
	return null
