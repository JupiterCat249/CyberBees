extends Node
## 迭代064 视图层回归自检（把本轮所有视图修复固化成**可重跑断言**）
## ---------------------------------------------------------------------------
## 运行：`project_run(mode="custom", scene="res://verification/iter064_view_check.tscn")`
##   （或用编辑器 F6 打开本场景运行）。**不需要**联机中继 —— 纯视图层断言。
##
## 覆盖（迭代064 各批次）：
##   B1 效果类三条信号已接线（修 P-21 徽标残存）
##   B3 手牌灰化只压 RGB、不压 alpha（修 P-05）
##   B4 卡上目标标框 set_mark（修 P-13）
##   B7 移除按钮进度条 / 详情区去技能名 / 右下面板不被阶段文案覆盖 /
##      主按钮长文案恒居中 / 费用两位数恒居中且不溢出徽章（修 P-17 · P-04 · P-09 · P-11 · P-06）
##   B8 单位卡电子管特效静止且无色变（修 P-02）
##   B2 HUD 随座位换边且可逆（修 P-07）
##   P-12 地图边框压在卡之上（修 UI-10 边缘蹭线）
##
## ⚠️ GDScript 闭包按值捕获 → 断言计数一律用**成员变量**
## ⚠️ Label 的尺寸在文本变更后**下一帧**才更新（Control 最小尺寸回写）→ 断言前须 await 若干帧
## ⚠️ 全部用例都带判空 —— 缺节点时判 FAIL 而不是崩（崩了整份报告就没了）
## ---------------------------------------------------------------------------
const BATTLE := preload("res://scenes/ui/battle_scene.tscn")
const Bus := preload("res://scripts/battle/battle_signal_bus.gd")

var _pass := 0
var _fail := 0
var _view: Node = null


func _ok(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS  ", label, detail)
	else:
		_fail += 1
		print("  FAIL  ", label, detail)


func _idle(frames: int = 2) -> void:
	for _i in frames:
		await get_tree().process_frame


func _first_hand_card() -> Control:
	var nodes = _view.get("_hand_nodes")
	if nodes == null:
		return null
	for sidek in nodes.keys():
		var d = nodes[sidek]
		for k in d.keys():
			var n = d[k]
			if n != null and is_instance_valid(n):
				return n
	return null


func _first_unit_card() -> Control:
	var nodes = _view.get("_unit_nodes")
	if nodes == null:
		return null
	for k in nodes.keys():
		var n = nodes[k]
		if n != null and is_instance_valid(n):
			return n
	return null


func _ready() -> void:
	print("=== 迭代064 视图层回归自检 ===")
	_view = BATTLE.instantiate()
	add_child(_view)
	await _idle(4)

	await _check_b1()
	await _check_b3()
	await _check_b4()
	await _check_b7()
	await _check_b8()
	await _check_b2()
	_check_p12()
	await _check_p03()

	print("=== 结果：%d PASS / %d FAIL ===" % [_pass, _fail])


## P-03（清单 UI-3/UI-4/UI-18）：**部署阶段点单位不给范围**（视图侧应为零高亮）；
## 而**可用的手牌**在部署阶段应给出部署格 —— 两条对照，确保不是"一律不显示"。
func _check_p03() -> void:
	var eng = _view.get("engine")
	var nodes = _view.get("_unit_nodes")
	var cells = _view.get("_cells")
	if eng == null or nodes == null or cells == null:
		_ok("P-03 取到引擎/单位表/格子表", false)
		return
	var u = null
	for k in nodes.keys():
		var iu = _view.call("_find_unit", String(k))
		if iu != null:
			u = iu
			break
	if u == null:
		_ok("P-03 取到场上单位", false)
		return
	## 回合 1 开局应为**部署阶段**（phase=2）；若已被推进则明确报出，避免误判
	if int(eng.state.phase) != 2:
		_ok("P-03 开局处于部署阶段", false, " phase=%d" % int(eng.state.phase))
		return
	eng.call("select_unit", 0, u)
	await _idle(3)
	var pv = _view.get("_preview")
	_ok("P-03 部署阶段选单位 → 预览为空（UI-3/UI-18）",
		pv == null or pv.cells.size() == 0,
		" cells=%d" % (0 if pv == null else pv.cells.size()))
	var any_hl := false
	for c in cells.keys():
		if cells[c].highlight != "":
			any_hl = true
			break
	_ok("P-03 部署阶段选单位 → 棋盘零高亮（UI-3）", not any_hl)
	## 对照组：可用的手牌必须仍给部署格（否则说明把该显示的也关掉了）
	var idx := -1
	var hand: Array = eng.state.sides[0]["hand"]
	for i in hand.size():
		if eng.call("can_play_hand", 0, i):
			idx = i
			break
	if idx < 0:
		_ok("P-03 找到一张可用手牌（对照组）", false)
		return
	eng.call("select_hand", 0, idx)
	await _idle(3)
	var pv2 = _view.get("_preview")
	_ok("P-03 对照：可用手牌仍给部署格（UI-4 反向）",
		pv2 != null and pv2.cells.size() > 0,
		" cells=%d" % (0 if pv2 == null else pv2.cells.size()))


## B1：效果类三条信号必须已接线（否则"引擎变了界面没变"会复发）
func _check_b1() -> void:
	var b := Bus.shared()
	_ok("B1 已订阅 effect_granted",
		b.is_connected(Bus.SIG_EFFECT_GRANTED, Callable(_view, "_on_effect_granted")))
	_ok("B1 已订阅 effect_expired",
		b.is_connected(Bus.SIG_EFFECT_EXPIRED, Callable(_view, "_on_effect_expired")))
	_ok("B1 已订阅 unit_stats_changed",
		b.is_connected(Bus.SIG_UNIT_STATS, Callable(_view, "_on_unit_stats_changed")))


## B3：手牌灰化**只压 RGB、alpha 恒 1**（费用图标/数字不得半透明）
func _check_b3() -> void:
	var c := _first_hand_card()
	if c == null:
		_ok("B3 取到手牌卡", false, "（无手牌节点）")
		return
	c.call("set_playable", false)
	var m: Color = c.modulate
	_ok("B3 灰化后 alpha 仍为 1（费用标记不半透明）", is_equal_approx(m.a, 1.0), " a=%.2f" % m.a)
	_ok("B3 灰化确实压了 RGB", m.r < 1.0 and is_equal_approx(m.r, m.g), " r=%.2f" % m.r)
	c.call("set_playable", true)
	_ok("B3 set_playable(true) 复原", is_equal_approx(c.modulate.a, 1.0) and is_equal_approx(c.modulate.r, 1.0))


## B4：卡上目标标框（因 PITCH=250 而卡正好 250×250，格高亮会被整片盖住）
func _check_b4() -> void:
	var u := _first_unit_card()
	if u == null:
		_ok("B4 取到单位卡", false, "（无单位卡节点）")
		return
	u.call("set_mark", "attack")
	var mark := u.get_node_or_null("Mark") as Control
	_ok("B4 set_mark 生成标框且可见", mark != null and mark.visible)
	if mark != null:
		_ok("B4 标框 z_index 高于卡面内容", mark.z_index >= 2, " z=%d" % mark.z_index)
		var sb := mark.get_theme_stylebox("panel")
		_ok("B4 攻击标框用红橙 #e8663c",
			sb is StyleBoxFlat and (sb as StyleBoxFlat).border_color.to_html(false) == "e8663c")
		_ok("B4 标框与卡面等大重合",
			mark.get_global_rect().size.is_equal_approx(u.get_global_rect().size))
	u.call("set_mark", "")
	var m2 := u.get_node_or_null("Mark") as Control
	_ok("B4 set_mark(\"\") 隐藏标框", m2 != null and not m2.visible)


## B7：文本与参数（进度条 / 技能名 / 地图机制面板 / 两处居中）
func _check_b7() -> void:
	var bar := _view.get_node_or_null("HUD/ActionBar") as Control
	var lb := _view.get_node_or_null("HUD/ActionBar/Label") as Control
	_ok("B7 主按钮进度条 MainButtonSeg 已移除",
		_view.get_node_or_null("HUD/ActionBar/MainButtonSeg") == null)
	if bar != null and lb != null:
		lb.text = "绿方胜（蜂王被击杀）"
		await _idle(3)
		_ok("B7 长文案下按钮文案仍居中",
			absf(lb.position.x - (bar.size.x - lb.size.x) * 0.5) < 1.0,
			" x=%.1f box=%.1f bar=%.1f" % [lb.position.x, lb.size.x, bar.size.x])
		lb.text = "完成部署"
		await _idle(2)

	## 详情区不再拼技能名（描述正文自带 [被动] 等前缀）
	var c := _first_hand_card()
	if c != null:
		var cd = c.get("card_data")
		if cd != null:
			_view.call("show_detail", cd)
			await _idle(2)
			var desc := _view.get_node_or_null("HUD/InfoPanel/SkillDesc") as Label
			var sn := String(cd.skill_name)
			_ok("B7 详情区不显示技能名",
				desc != null and (sn == "" or not desc.text.contains(sn)),
				" skill_name=「%s」" % sn)
	else:
		_ok("B7 取到手牌卡（详情区检查用）", false, "（无手牌节点）")

	## 右下面板不得被阶段文案覆盖（应保留地图机制）
	var se := _view.get_node_or_null("HUD/MatchInfo/SiteEffect") as Label
	if se != null:
		var before := se.text
		_view.call("_on_phase_started", 0, 2, 1)
		_ok("B7 阶段文案不再覆盖地图机制面板", se.text == before, " 「%s」" % se.text)
	else:
		_ok("B7 取到 SiteEffect", false)

	## 费用两位数：恒居中且不溢出徽章
	for sidep in ["Battle/PlayerBesaInfoRight", "Battle/PlayerBesaInfoLift"]:
		var badge := _view.get_node_or_null(sidep + "/BadgeImage") as Control
		if badge == null:
			_ok("B7 取到费用徽章 %s" % sidep, false)
			continue
		var v := badge.get_node_or_null("Value") as Control
		if v == null:
			_ok("B7 取到费用数字 %s" % sidep, false)
			continue
		v.text = "10"
		await _idle(3)
		_ok("B7 两位数费用恒居中 %s" % sidep,
			absf(v.position.x - (badge.size.x - v.size.x) * 0.5) < 1.0,
			" x=%.1f w=%.1f badge=%.1f" % [v.position.x, v.size.x, badge.size.x])
		_ok("B7 两位数费用不溢出徽章 %s" % sidep,
			v.get_global_rect().end.x <= badge.get_global_rect().end.x + 0.5,
			" text_end=%.1f badge_end=%.1f" % [v.get_global_rect().end.x, badge.get_global_rect().end.x])


## B8：单位卡电子管特效 —— 不自动播放、不运动、无颜色变换
func _check_b8() -> void:
	var u := _first_unit_card()
	if u == null:
		_ok("B8 取到单位卡", false)
		return
	var anim := u.get_node_or_null("Artwork/ArtPlane/CrtFx/CrtAnim") as AnimationPlayer
	var mover := u.get_node_or_null("Artwork/ArtPlane/CrtFx/Mover") as Control
	if anim == null or mover == null:
		_ok("B8 取到 CrtFx 子节点", false)
		return
	_ok("B8 电子管动画未自动播放", not anim.is_playing() and String(anim.autoplay) == "",
		" autoplay=「%s」playing=%s" % [String(anim.autoplay), str(anim.is_playing())])
	var p0 := mover.position
	await _idle(10)
	_ok("B8 电子管特效不运动", (mover.position - p0).length() < 0.01,
		" Δ=%.3f" % (mover.position - p0).length())
	_ok("B8 电子管特效无颜色变换（self_modulate 为白）",
		mover.self_modulate.is_equal_approx(Color(1, 1, 1, 1)),
		" %s" % str(mover.self_modulate))


## B2：HUD 随座位换边，且切回座位 0 能精确还原
func _check_b2() -> void:
	var hl := _view.get_node_or_null("Battle/HandPanelLeft") as Control
	var hr := _view.get_node_or_null("Battle/HandPanelRight") as Control
	if hl == null or hr == null:
		_ok("B2 取到手牌面板", false)
		return
	var l0 := hl.position.x
	var r0 := hr.position.x
	_view.call("set_my_seat", 1)
	_ok("B2 镜像后我方（左面板）换到右侧", hl.position.x > hr.position.x,
		" L=%.0f R=%.0f" % [hl.position.x, hr.position.x])
	_view.call("set_my_seat", 0)
	_ok("B2 切回座位 0 精确还原", is_equal_approx(hl.position.x, l0) and is_equal_approx(hr.position.x, r0),
		" L=%.0f(原 %.0f) R=%.0f(原 %.0f)" % [hl.position.x, l0, hr.position.x, r0])


## P-12：地图边框（纯描边无填充）必须压在单位卡之上，否则边缘卡会截断框线
func _check_p12() -> void:
	var mf := _view.get_node_or_null("Battle/MapView/MapFrame") as Control
	var un := _view.get_node_or_null("Battle/MapView/Units") as Control
	if mf == null or un == null:
		_ok("P-12 取到 MapFrame / Units", false)
		return
	_ok("P-12 地图边框 z_index 高于单位卡容器", mf.z_index > un.z_index,
		" frame=%d units=%d" % [mf.z_index, un.z_index])
