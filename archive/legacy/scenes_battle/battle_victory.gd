extends RefCounted
## ============================================================
## BattleVictory —— 胜负判定 块（可维护性重构 第6块·下·之一）
##
## 从 battle_state.gd 搬出：check_victory / queen_alive / queen_hp / round12_result
##
## 规则依据（a500 胜利条件）：
##   · 蜂王归零即判负（双方同时归零为平局）
##   · 第 12 回合结束时按蜂王剩余生命值比较，高者胜、相同为平局
##   · 胜负确定后发 battle_ended 信号（视图据此进入结算表现）
## ============================================================

## 由协调器注入（共享 Model）
var state: Node = null


## 胜负判定：任一方蜂王不在场即判定（双方都不在=平局）
func check_victory() -> void:
	var s := state
	if s.winner != "":
		return
	var gq: bool = queen_alive("green")
	var rq: bool = queen_alive("red")
	if not gq and not rq:
		s.winner = "draw"
	elif not gq:
		s.winner = "red"
	elif not rq:
		s.winner = "green"
	if s.winner != "":
		s.push_log("游戏结束：%s" % ("平局" if s.winner == "draw" else s.cn(s.winner) + "方 获胜"))
		s.battle_ended.emit(s.winner)


func queen_alive(side: String) -> bool:
	var s := state
	for id in s.units:
		if s.units[id]["side"] == side and s.units[id]["card"]["kind"] == "queen":
			return true
	return false


func queen_hp(side: String) -> int:
	var s := state
	for id in s.units:
		if s.units[id]["side"] == side and s.units[id]["card"]["kind"] == "queen":
			return int(s.units[id]["hp"])
	return 0


## 第12回合结束：按蜂王剩余生命值比较（a500 胜利条件 2）
func round12_result() -> void:
	var s := state
	if s.winner != "":
		return
	var gh: int = queen_hp("green")
	var rh: int = queen_hp("red")
	if gh == rh:
		s.winner = "draw"
	else:
		s.winner = "green" if gh > rh else "red"
	s.push_log("第12回合结束：蜂王血量 绿%d / 红%d → %s" % [gh, rh, "平局" if s.winner == "draw" else s.cn(s.winner) + "方 获胜"])
	s.battle_ended.emit(s.winner)
