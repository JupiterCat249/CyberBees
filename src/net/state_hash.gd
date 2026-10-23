class_name StateHash
extends RefCounted
## 战斗状态指纹（**确定性比对用**）
## ---------------------------------------------------------------------------
## 用途：① 联机一致性比对（迭代061 检查点 2）② 回放/调试复现 ③ 将来可下沉 GDExtension/C++
## 铁律：**只读 state**（不写任何字段）；字段顺序与单位排序固定 —— 同一 seed + 同一操作序列必须得到同一串
## ⚠️ 已知取舍：效果只计入**数量**（`effects.size()`），不计内容 ——
##    若后续需要更严的比对，再扩到效果 id/层数（需先核实 EffectRuntime 字段名，不猜）
## ---------------------------------------------------------------------------


## 可读指纹（排错时看这个）
static func of(state: BattleState) -> String:
	if state == null:
		return "null"
	var p: Array[String] = []
	p.append("r%d" % state.round_no)
	p.append("a%d" % state.active)
	p.append("ph%d" % state.phase)
	p.append("res%d" % state.result)
	for side: int in [BattleState.SIDE_ALLY, BattleState.SIDE_ENEMY]:
		p.append("c%d=%d" % [side, state.cost(side)])
		p.append("h%d=%s" % [side, _ids(state.hand(side))])
		p.append("dk%d=%s" % [side, _ids(state.deck(side))])
		p.append("ds%d=%s" % [side, _ids(state.discard(side))])
	p.append("u=%s" % _units(state))
	return "|".join(PackedStringArray(p))


## 短指纹（两端比对用）
static func sha(state: BattleState) -> String:
	return of(state).sha256_text()


static func _ids(arr: Array) -> String:
	var out: Array[String] = []
	for c in arr:
		out.append(String(c.id) if c != null else "-")
	return ",".join(PackedStringArray(out))


## 单位指纹：**不得用 instance_id**（它是随机 UUIDv4，见 `data/unit_instance.gd` → 两端各不相同），
## 改用「卡 id + 位置 + 血量 + 行动位」这类**跨端稳定**的字段（迭代061 实测教训）
static func _units(state: BattleState) -> String:
	var out: Array[String] = []
	for u in state.all_units():
		if u == null:
			continue
		var mv := 1 if u.has_moved else 0
		var ac := 1 if u.has_acted else 0
		var cid := String(u.data.id) if u.data != null else "?"
		out.append("%s/%d@%d,%d/hp%d/mv%d/ac%d/fx%d" % [
			cid, int(u.side), u.cell.x, u.cell.y,
			int(u.current_hp), mv, ac, u.effects.size()
		])
	out.sort()
	return ";".join(PackedStringArray(out))
