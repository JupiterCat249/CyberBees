extends Node
## BattleAnimDriver —— 动画**推进器 +（检查点6 起）接线**：生产侧唯一来源
##
## 边界与依据
##   · T3 v1.10（人 2026-09-21）：动画系统＝**手牌 + 单位**；实现＝节点 + 动画编辑器/资源数据驱动，
##     **代码最少化** —— 本类只做「注册推进」与「信号 → play(名)」，不实现任何动画逻辑。
##   · T2 + 回放一致性：**动画进度必须是帧数的纯函数** —— 动画节点一律以
##     `callback_mode_process = MANUAL` 运行，由本类**每帧 advance(1/60) 恰好一次**；
##     **禁止**使用 `delta` / 真实时间 / `speed_scale` 随机，否则回放不可复现。
##
## 帧数契约（写动画资源时必须遵守）
##   时长(秒) = 帧数 / 60   ·   Animation.step = 1/60
##   受击 40 帧 = 0.6667s · 地图 60 帧 = 1.0s · 飘字 60 帧 = 1.0s · 退场 20 帧 = 0.3333s
const FRAME := 1.0 / 60.0

var _players: Array = []


## 注册一个动画节点（单位卡 / 手牌卡 / 飘字的 AnimationPlayer）
func register_player(p: AnimationPlayer) -> void:
	if p == null or _players.has(p):
		return
	p.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_players.append(p)


func unregister_player(p: AnimationPlayer) -> void:
	_players.erase(p)


## 播放统一入口（检查点6 在此集中「信号 → 动画名」映射）
func play(p: AnimationPlayer, anim: StringName) -> void:
	if p == null or not p.has_animation(anim):
		push_warning("BattleAnimDriver: 缺少动画 %s" % anim)
		return
	p.play(anim)


func _process(_delta: float) -> void:
	## 帧数计时：每帧推进**恰好一帧**，不读 `_delta`（T2）
	## ⚠️ 先复制一份再遍历（迭代034 教训：回调可能增删运行表）
	for p in _players.duplicate():
		if is_instance_valid(p) and p.is_playing():
			p.advance(FRAME)
