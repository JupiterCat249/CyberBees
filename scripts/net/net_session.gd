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


static func clear() -> void:
	url = ""
	room_code = ""
	seat = 0
	seed_value = 0
	first_side = 0
	active = false


static func describe() -> String:
	return "房间 %s · 座位 %d · seed %d · 先手 %d" % [room_code, seat, seed_value, first_side]
