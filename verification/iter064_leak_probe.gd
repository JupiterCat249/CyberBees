extends Node
## 【验证用 · 非生产】迭代064 遗留修复 · **新两问诊断探针 v6**
##  ① 单位卡「变黑」（时序问题）：`TINT` 类动画是否会**覆盖**卡面 modulate（卡牌登场淡入 / 受伤闪红 / 单位退场）
##  ② 左侧详情栏文本溢出：`SkillDesc` 的实际 rect / 文本尺寸 / autowrap 配置
## 运行：project_run(mode="custom", scene="res://verification/iter064_leak_probe.tscn")
## 一律无类型 var
## ---------------------------------------------------------------------------
const BATTLE := preload("res://scenes/ui/battle_scene.tscn")
const TINT_KIND := 2          ## anim_clip.gd 的 Kind.TINT（F 枚举镜像，仅用于探针打印）

var _view: Node = null
var _eng = null


func _idle(n: int = 2) -> void:
	for _i in n:
		await get_tree().process_frame


func _ready() -> void:
	print("=== 探针 v6 · 新两问诊断 ===")
	_view = BATTLE.instantiate()
	add_child(_view)
	await _idle(6)
	_eng = _view.get("engine")
	await _case_tint()
	_case_detail_overflow()
	print("PROBE DONE")
	get_tree().quit()


# ------------------------------------------------------------
#  ① TINT 动画对卡面 modulate 的影响
# ------------------------------------------------------------
func _case_tint() -> void:
	print("--- ① 单位卡 modulate 与 TINT 动画 ---")
	var mine = _pick(0)
	if mine == null:
		print("① 跳过：无单位")
		return
	var node = _view.get("_unit_nodes").get(mine.instance_id, null)
	if node == null:
		print("① 跳过：无卡节点")
		return
	print("① 开场 modulate=%s（bind 后应为白或已行动色）" % str(node.modulate))

	## ① A：卡牌登场（淡入）动画期间，卡面 modulate 怎么变
	_view.call("_play", "卡牌登场", mine)
	await _idle(2)
	print("①A 播『卡牌登场』后 modulate=%s" % str(node.modulate))
	## ① A2：在淡入动画**仍在播**时让该单位“已行动”（模拟“第一回合第一个攻击的单位”的时序）
	_view.call("_rebind_unit", mine)     # 绑定一次（本例 acted 仍为 false，先看基线）
	await _idle(1)
	print("①A2 淡入中 bind 一次 → modulate=%s" % str(node.modulate))

	## ① B：受伤闪红对**已行动色**的覆盖
	await _idle(8)
	mine.mark_acted()
	_view.call("_rebind_unit", mine)
	await _idle(1)
	print("①B 标记已行动后 modulate=%s（期望=冷灰蓝 0.62,0.68,0.78）" % str(node.modulate))
	_view.call("_play", "受伤闪红", mine, 3)
	for i in 4:
		await get_tree().process_frame
		print("     受伤闪红 t+%d frames → %s" % [i + 1, str(node.modulate)])
	await _idle(8)
	print("①B 闪红播完后 modulate=%s（若=纯白则『已行动色被顺带抹掉』）" % str(node.modulate))

	## ① C：单位退场（淡出）到腰时的 modulate
	_view.call("_play", "单位退场", mine)
	await _idle(10)
	print("①C 单位退场进行中 modulate=%s" % str(node.modulate))


# ------------------------------------------------------------
#  ② 详情栏溢出
# ------------------------------------------------------------
func _case_detail_overflow() -> void:
	print("--- ② 左侧详情栏（InfoPanel）文本溢出 ---")
	var ds := _view.get_node_or_null("HUD/InfoPanel/SkillDesc") as Label
	var nm := _view.get_node_or_null("HUD/InfoPanel/CardName") as Label
	var panel := _view.get_node_or_null("HUD/InfoPanel") as Control
	if ds == null or panel == null:
		print("② 跳过：取不到 InfoPanel/SkillDesc")
		return
	print("② InfoPanel rect=%s" % str(panel.get_global_rect()))
	var info_r := panel.get_global_rect().end.x
	for pair in [["CardName", nm], ["SkillDesc", ds]]:
		var label: Label = pair[1]
		if label == null:
			continue
		var gr: Rect2 = label.get_global_rect()
		var minw: float = label.get_theme_font("font").get_string_size(
			label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			label.get_theme_font_size("font_size")).x
		print("② %s: rect_x=%.1f w=%.1f 右缘=%.1f · 面板右缘=%.1f · 溢出=%.1f · 单行文本宽=%.1f · autowrap=%d · clip=%s · 行数=%d" % [
			String(pair[0]), gr.position.x, gr.size.x, gr.end.x, info_r,
			gr.end.x - info_r, minw, int(label.autowrap_mode),
			str(label.clip_text), label.get_line_count()])
		print("       文本=「%s」" % label.text.replace("\n", "⏎"))
	## 与右侧（已修好的）SiteEffect 对比：它已设 autowrap
	var se := _view.get_node_or_null("HUD/MatchInfo/SiteEffect") as Label
	if se != null:
		print("② 对照 SiteEffect autowrap=%d（已设自动换行的标杆）" % int(se.autowrap_mode))


func _pick(side: int):
	for u in _eng.state.board.all_units():
		if u.side == side:
			return u
	return null
