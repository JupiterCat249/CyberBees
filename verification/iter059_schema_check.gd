extends Node
## 【验证用 · 非生产】迭代059：**资源 schema 同步校验**
## 背景（人实测缺陷）：代码改了 `EffectData` / 卡池工厂，但 `game_data/*.tres` 里
##   还是**旧的序列化值**（装甲 `dmg_reduce = 2`、无 `blocks_attack`），
##   而游戏加载的是 .tres → **代码改动根本没生效**。
## 本脚本守住这条：.tres 必须与代码口径一致。
##
## 用法：project_run(mode="custom", scene="res://verification/iter059_schema_check.tscn")

const Pool := preload("res://scripts/data/card_pool.gd")
const Combat := preload("res://scripts/battle/rules_combat.gd")
const Eng := preload("res://scripts/battle/battle_engine.gd")
const ConfigLib := preload("res://scripts/battle/battle_config.gd")
const StateLib := preload("res://scripts/battle/battle_state.gd")

var _pass := 0
var _fail := 0
var _failures: Array[String] = []


func _ready() -> void:
	print("\n===== 迭代059：资源 schema 同步校验 =====")
	## ⚠️ 必须有常驻节点，否则 `await get_tree().process_frame` 在本测试树里不触发
	##   （本仓自检里已多次踩到：无场景的 await 会**静默停止**，连 print 都不出来）
	var keep := Control.new()
	keep.name = "KeepAlive"
	add_child(keep)
	_t_armor_tres()
	_t_no_stale_reduce()
	_t_load_shadowing()
	await _t_hand_mask_active()
	_report()
	get_tree().quit(0 if _fail == 0 else 1)


## ① 装甲资源必须写 blocks_attack（旧 .tres 里没有这个字段 → 失效）
func _t_armor_tres() -> void:
	_section("① 装甲效果资源（游戏实际加载的 .tres）")
	var p := "res://game_data/cards/金刚蜂王.tres"
	var txt := FileAccess.get_file_as_string(p)
	_chk("金刚蜂王.tres 存在且非空", txt.length() > 0)
	_chk("装甲子资源写入了 blocks_attack", txt.contains("blocks_attack = true"))
	_chk("装甲**不再**写 dmg_reduce = 2（旧值）", not txt.contains("dmg_reduce = 2"))
	_chk("技能描述不再写「受到的每次伤害 -1」（旧文案）",
		not txt.contains("受到的每次伤害 -1"))
	# 回读实测：加载出来的卡必须能完全抵挡
	var ud = load(p)
	_chk("回读卡资源成功", ud != null)
	var found := false
	for sk in ud.skills:
		for ef in sk.effects:
			if ef.display_name == "装甲":
				found = true
				_chk("回读的装甲 blocks_attack = true", ef.blocks_attack)
				_chk("回读的装甲 dmg_reduce = 0（不是数值减伤）", ef.dmg_reduce == 0)
	_chk("卡里确实有「装甲」效果", found)


## ② 所有卡资源不得残留「按层数/数值减伤」的旧口径文本
func _t_no_stale_reduce() -> void:
	_section("② 卡资源无旧口径残留")
	var da := DirAccess.open("res://game_data/cards")
	_chk("能打开卡资源目录", da != null)
	var bad: Array = []
	for f in da.get_files():
		if not f.ends_with(".tres"):
			continue
		var t := FileAccess.get_file_as_string("res://game_data/cards/" + f)
		if t.contains("dmg_reduce = ") and not t.contains("dmg_reduce = 0"):
			bad.append(f)
	_chk("无卡资源残留非零 dmg_reduce（%s）" % str(bad), bad.is_empty())


## ③ 加载阴影验证：加载出来的单位确实能完全抵挡（不只看文件文本）
func _t_load_shadowing() -> void:
	_section("③ 加载出的单位行为与代码一致")
	var e = Eng.new()
	e.start(ConfigLib.make(Pool.build("资A"), Pool.build("资B")))
	var st = e.state
	var q: UnitInstance = st.queen(0)
	var has := false
	for ef in q.effects:
		if ef.data != null and ef.data.display_name == "装甲":
			has = true
			_chk("场上蜂王的装甲 blocks_attack = true", ef.data.blocks_attack)
			_chk("场上蜂王的装甲 dmg_reduce = 0", ef.data.dmg_reduce == 0)
	_chk("蜂王自带装甲", has)
	_chk("对持装甲者原始伤害 = 0（完全抵挡）",
		Combat.raw_damage(st.queen(1), q, st.board) == 0)


## ④ 回合轮换后手牌可出性与显示一致（人实测缺陷：轮换后整手灰）
func _t_hand_mask_active() -> void:
	_section("④ 回合轮换后手牌可出性基于**当前行动方**")
	var e = Eng.new()
	e.start(ConfigLib.make(Pool.build("轮A"), Pool.build("轮B")))
	var st = e.state
	var start_active: int = st.active
	## `request_end_phase` 仅在 DEPLOY / ACTION 可推进（回费/场地由引擎自动结算）
	##   → 等待帧让自动阶段走完，再在可推进的阶段点一次
	for _n in 30:
		if st.active != start_active:
			break
		if st.phase == StateLib.Phase.DEPLOY or st.phase == StateLib.Phase.ACTION:
			e.request_end_phase()
		await get_tree().process_frame
	print("    轮换后 active = %d（起始 %d），绿费=%d 红费=%d" % [
		st.active, start_active, st.cost(0), st.cost(1)])
	_chk("回合已轮换到另一方", st.active != start_active)
	var active_side: int = st.active
	## 当前行动方：其手牌的可出性判定应基于**它自己**
	var hand_a: Array = st.hand(active_side)
	var playable_a := 0
	for i in hand_a.size():
		if e.can_play_hand(active_side, i):
			playable_a += 1
	print("    当前行动方手牌 %d 张，其中可出 %d 张（费=%d）" % [
		hand_a.size(), playable_a, st.cost(active_side)])
	_chk("当前行动方**不是整手不可出**（低费牌应可出）", playable_a > 0)
	## 非行动方：一律不可出
	var other: int = 1 - active_side
	var cnt_other := 0
	for i in st.hand(other).size():
		if e.can_play_hand(other, i):
			cnt_other += 1
	_chk("非行动方全部不可出（mask 跟随 active）", cnt_other == 0)
	## 费用下限校验：若当前方费用 ≥ 其最低费牌，则至少那 1 张必须可出
	var min_cost := 999
	for c in hand_a:
		if c != null and c.cost >= 0:
			min_cost = mini(min_cost, int(c.cost))
	if min_cost != 999 and st.cost(active_side) >= min_cost:
		_chk("费用足够最低费牌（%d ≤ %d）→ 至少 1 张可出" % [min_cost, st.cost(active_side)],
			playable_a >= 1)


func _section(t: String) -> void:
	print("\n--- %s ---" % t)


func _chk(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  [PASS] ", label)
	else:
		_fail += 1
		_failures.append(label)
		print("  [FAIL] ", label)


func _report() -> void:
	print("\n===== schema 校验结果 =====")
	print("  通过 %d / 失败 %d" % [_pass, _fail])
	for f in _failures:
		print("   X ", f)
	print("==========================")
