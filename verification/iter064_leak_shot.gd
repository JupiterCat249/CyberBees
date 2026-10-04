extends Node
## 【验证用 · 非生产】详情栏**换行能力**对照取证（用确定会溢出的长文案压测）
## 为何需要：本批卡面描述都偏短（最长行 < 300px 框宽）⇒ 实机截图无法暴露换行能力。
## 做法：给 `SkillDesc` 灌一段长中文（模拟“超过 300px 的技能说明”），采样
##       rect / 行数 / 最长行宽 —— 换行开启后行数↑、最长行宽 ≤ 框宽。
## 运行：project_run(mode="custom", scene="res://verification/iter064_leak_shot.tscn")
## 产物：user://shot_wrap_pressure.png
## ---------------------------------------------------------------------------
const BATTLE := preload("res://scenes/ui/battle_scene.tscn")
var _view: Node = null


func _idle(n: int = 2) -> void:
	for _i in n:
		await get_tree().process_frame


func _ready() -> void:
	print("=== 详情栏换行 · 长文案压测 ===")
	_view = BATTLE.instantiate()
	add_child(_view)
	await _idle(6)
	var ds := _view.get_node_or_null("HUD/InfoPanel/SkillDesc") as Label
	var panel := _view.get_node_or_null("HUD/InfoPanel") as Control
	if ds == null or panel == null:
		print("跳过：取不到节点")
		get_tree().quit()
		return
	var long_text := "[被动]在敌方领地时，攻击造成两倍伤害；若目标为蜂王则额外获得一层护盾，并在下次受击时优先抵挡全部伤害。"
	print("压测文案长=%d 字 · 框宽=%.0f · 面板右缘=%.0f" % [
		long_text.length(), ds.size.x, panel.get_global_rect().end.x])
	ds.text = long_text
	await _idle(4)
	## ⚠️ Label 没有 `get_line()`（实测踩到：Invalid call → 游戏被停进断点）
	##   判据改用：① 行数（换行后 > 1）② **所需高度**（Word 换行时高度会随行数增长）；
	##   同时用「单行渲染所需宽度 vs 框宽」给出一条可判真伪的读数。
	var need_w := ds.get_theme_font("font").get_string_size(
		long_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, ds.get_theme_font_size("font_size")).x
	var no_wrap_h := ds.get_theme_font_size("font_size")
	var lines: int = ds.get_line_count()
	var actual_h: float = ds.size.y
	print("判定A：autowrap=%d · 行数=%d · 所需单行宽=%.1f · 框宽=%.1f · 单行必溢出=%s" % [
		int(ds.autowrap_mode), lines, need_w, ds.size.x, str(need_w > ds.size.x)])
	## Word Smart 换行后的近似行数（按框宽整除，用于验证"行数确实随换行增长"）
	var approx_lines: int = int(ceil(need_w / maxf(1.0, ds.size.x - 4.0)))
	print("判定B：按框宽估算应折行数=%d · 实际行数=%d · 行数≥估算=%s" % [
		approx_lines, lines, str(lines >= approx_lines - 1)])
	print("判定C：控件实际高度=%.1f（换行开启后高度会随行数增长；单行时约=字号 %d）" % [
		actual_h, no_wrap_h])
	await _shot("user://shot_wrap_pressure.png")
	print("=== 压测完成 ===")
	get_tree().quit()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var e := img.save_png(path)
	print("SHOT %s err=%d" % [path, e])
