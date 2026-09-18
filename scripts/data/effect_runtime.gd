class_name EffectRuntime
extends RefCounted
## 效果的运行态（挂在 UnitInstance 上）；静态数据在 EffectData

var data: EffectData
var turns: int = -1              ## 剩余回合；-1 = 永久


func _init(p_data: EffectData = null) -> void:
	data = p_data
	if p_data != null:
		turns = p_data.duration


func tick() -> bool:
	## 返回是否应移除
	if turns < 0:
		return false
	turns -= 1
	return turns <= 0
