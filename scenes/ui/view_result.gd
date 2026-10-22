extends RefCounted
## 结算浮层构造（自 arena_view 切出 —— 迭代087 · B5 第十刀）
##
## 人 2026-09-21/10-10 裁定（原样保留）：
##   · 浮层**保留战场画面**（不切场景、不清屏）；
##   · 「再来一局」＝回大厅后重新匹配；
##   · 掉线随时可手动返回。
##
## 判据：只**构造**面板（标题/明细/按钮接线），不切场景、不碰联机状态 ——
##   那些留在视图（`_leave_and_go`），因为它们是"收尾流程"而不是"渲染"。

static func build_panel(panel_script: Script, result: int, reason: String, net_seat: int,
		engine, room_code: String, is_net: bool, on_rematch: Callable, on_lobby: Callable) -> Control:
	## 幂等由调用方保证（视图侧已判空）
	var title := "对局结束"
	match int(result):
		1: title = "绿方胜"
		2: title = "红方胜"
		3: title = "平局"
	if int(result) == 1 or int(result) == 2:
		var my_win: bool = (int(result) == 1 and net_seat == 0) or (int(result) == 2 and net_seat == 1)
		title = ("胜利" if my_win else "失败") + "（" + title + "）"
	var lines: Array[String] = []
	lines.append("我的座位：%d（%s）" % [net_seat, "绿方" if net_seat == 0 else "红方"])
	if engine != null and engine.state != null:
		lines.append("回合数：%d" % int(engine.state.round_no))
		lines.append("状态指纹：%s" % StateHash.sha(engine.state).substr(0, 12))
	if is_net:
		lines.append("房间：%s" % room_code)
	var panel := Control.new()
	panel.set_script(panel_script)
	panel.setup(title, reason, lines)      ## ⚠️ 必须在 add_child 之前（_ready 里要用这些字段建 UI）
	panel.rematch_pressed.connect(on_rematch)
	panel.lobby_pressed.connect(on_lobby)
	return panel
