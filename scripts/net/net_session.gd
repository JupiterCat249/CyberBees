class_name NetSession
extends RefCounted
## 联机会话信息（大厅 → 战斗场景 的**唯一传递点**）
## ---------------------------------------------------------------------------
## 用 static var：**无需 autoload**；只存纯数据（不持有连接/节点）
## 约定：seat 0 ↔ 引擎 SIDE_ALLY（绿）· seat 1 ↔ 引擎 SIDE_ENEMY（红）
## ---------------------------------------------------------------------------
static var url: String = ""
static var room_code: String = ""
static var seat: int = 0
static var seed_value: int = 0
static var first_side: int = 0
static var active: bool = false


static func set_match(p_url: String, p_code: String, p_seat: int, p_seed: int, p_first: int) -> void:
	url = p_url
	room_code = p_code
	seat = p_seat
	seed_value = p_seed
	first_side = p_first
	active = true


## ⚠️ **连接必须跨场景共享**（迭代062 双实例实测教训）：房间/座位都挂在**连接**上，
##    若切场景时让大厅的连接被释放、战斗场景另起一条 → 新连接**不在房间里** → 两端各玩各的 ✗
static var client: RelayClient = null
## 结算后的去向（迭代063）：true = 回大厅后**自动重新入队**（«再来一局»）
static var rematch: bool = false
## 自动验收用：已完成的对局数（供自动模式连打两局）
static var games: int = 0


static func clear() -> void:
	url = ""
	room_code = ""
	seat = 0
	seed_value = 0
	first_side = 0
	active = false


## dev / 双实例验收用：自动匹配 + 自动出招
## 三个来源任一命中即开：`--net-auto` · `SB_NET_AUTO=1` · 存在 `res://net_config/auto.flag`
## （编辑器进程无法传 user args ↔ 环境变量也可能拿不到 → 用开关文件兜底）
static var auto: bool = false
static var final_hash: String = ""
static var auto_steps: int = 0


static func detect_auto() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a) == "--net-auto":
			auto = true
	if OS.get_environment("SB_NET_AUTO") == "1":
		auto = true
	if FileAccess.file_exists("res://net_config/auto.flag"):
		var f := FileAccess.open("res://net_config/auto.flag", FileAccess.READ)
		if f != null:
			var v := f.get_as_text().strip_edges().to_lower()
			f.close()
			if v == "1" or v == "true" or v == "on":
				auto = true


static func describe() -> String:
	return "房间 %s · 座位 %d · seed %d · 先手 %d" % [room_code, seat, seed_value, first_side]
