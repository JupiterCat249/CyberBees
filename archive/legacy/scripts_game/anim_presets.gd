class_name AnimPresets
extends RefCounted
## 默认动画 Pattern 注册表 —— **手感参数原样搬运自旧实测收敛值**
##
## 参数来源（全部是"人实机测试后的结论"，见 T15：手感类以实测为准）：
##   · `scenes/battle/battle_defs.gd` 的 SHAKE_* / FLOAT_TEXT_* 常量（迭代022~028 实测收敛）
##   · `scenes/battle/battle_anim.gd` 的 register_defaults()（迭代004~032 逐轮修订）
##   · `电子蜂A5策划案/动画系统及流程.md` 二、动画顺序与表现规范
##
## ⚠️ 本文件**只描述表现**，不含规则；帧数一律以帧为单位（T2）。

const AU := preload("res://scripts/game/action_unit.gd")
const U := AU.U

# ---------------- 手感常量（单一来源，改这里就够） ----------------

const SHAKE_FRAMES_UNIT := 36        ## 单位受击抖动：36 帧 ≈ 0.60s
const SHAKE_FRAMES_MAP := 54         ## AOE 地图抖动：54 帧 ≈ 0.90s
const SHAKE_DECAY := 0.88            ## 每段振幅衰减系数
const SHAKE_AMP_UNIT := 4.0          ## 单位受击基准振幅（px）
const SHAKE_AMP_MAP := 7.0           ## AOE 地图基准振幅（px）
const SHAKE_FRAMES_BONUS_MAX := 18   ## 高伤害延长量（36 → 54 帧）
const SHAKE_JITTER_AMP := 0.18       ## 每段振幅随机抖动（±18%）
const SHAKE_JITTER_STEPS := 2        ## 段数随机浮动（±2 段）

const FLOAT_TEXT_FRAMES := 60        ## 飘字显示时长：60 帧 = 1.0s
const FLOAT_TEXT_RISE_FRAMES := 40   ##   上浮占 40 帧（其余 20 帧淡出）
const FLOAT_TEXT_RISE := 60.0        ##   上浮总距离（px）

const TEXT_FS_BASE := 40             ## 数值 0 时的字号（设计空间 px）
const TEXT_FS_MAX := 96              ## 数值达上限时的字号
const TEXT_FS_VMAX := 10             ## 字号线性映射的上限数值

## 颜色（表现规范「UI状态与颜色映射」）
const DAMAGE_COLOR := Color("ff2000")     ## 受伤
const REFUND_COLOR := Color("ffa300")     ## 回费
const HEAL_COLOR := Color("00dd00")       ## 回血
const TURN_MINE := Color("499169")        ## 我方回合
const TURN_FOE := Color("a84331")         ## 敌方回合
const NEUTRAL_COLOR := Color(1, 1, 1, 0.5)  ## 中性/结束态 #FFFFFF-50%

const FONT_PATH := "res://assets/fonts/NotoSansSC-Bold.ttf"


static func turn_color(is_mine: bool) -> Color:
	return TURN_MINE if is_mine else TURN_FOE


static func text_size_for(value: int) -> int:
	var v: int = mini(absi(value), TEXT_FS_VMAX)
	var k: float = float(v) / float(TEXT_FS_VMAX)
	return int(round(lerpf(float(TEXT_FS_BASE), float(TEXT_FS_MAX), k)))


static func text_color(kind: String) -> Color:
	match kind:
		"damage": return DAMAGE_COLOR
		"refund": return REFUND_COLOR
		"heal":   return HEAL_COLOR
	return Color.WHITE


# ---------------- 注册 ----------------

## 把全部默认 Pattern 注册进引擎
static func register_all(eng: Node) -> void:
	_register_shake(eng, "受击抖动", SHAKE_AMP_UNIT, SHAKE_FRAMES_UNIT)
	_register_shake(eng, "地图抖动", SHAKE_AMP_MAP, SHAKE_FRAMES_MAP)
	eng.register("浮字上浮", _float_pattern())

	# 卡牌登场：瞬时动作（无前摇）—— 第 1 帧即到位，只做淡入
	eng.register("卡牌登场", {"units": [
		{"type": U.TINT, "clips": [{"frames": 4, "color": Color(1, 1, 1, 1.0)}]},
	]})
	# 卡牌退场：末帧即刻消失（无后摇）
	eng.register("卡牌退场", {"units": [
		{"type": U.TINT, "clips": [
			{"frames": 3, "color": Color(1, 0.6, 0.6, 1.0)},
			{"frames": 2, "color": Color(1, 1, 1, 0.0)},
		]},
	]})

	# 部署：落位下沉 → 回弹（无前摇）
	eng.register("部署落位", {"units": [
		{"type": U.MOVE_BY, "clips": [
			{"frames": 1, "step": Vector2(0, 8)},
			{"frames": 2, "step": Vector2(0, -8)},
		]},
	]})
	# 移动：仅一次轻微下沉回弹（迭代026 人实测：左右抖会与受击抖动混淆，故移除）
	eng.register("移动落位", {"units": [
		{"type": U.MOVE_BY, "clips": [
			{"frames": 1, "step": Vector2(0, 3)},
			{"frames": 1, "step": Vector2(0, -3)},
		]},
	]})
	# 使用指令：施放者闪白一次（第 1 帧即亮 = 无前摇）
	eng.register("施放闪白", {"units": [
		{"type": U.TINT, "clips": [{"frames": 1, "color": Color(1, 0.95, 0.6, 1)}]},
		{"type": U.TINT, "clips": [{"frames": 2, "color": Color.WHITE}]},
	]})
	# 数值 buff / 减益：目标变色脉冲
	eng.register("增益脉冲", {"units": [
		{"type": U.TINT, "clips": [
			{"frames": 1, "color": Color("66ff88")},
			{"frames": 3, "color": Color.WHITE},
		]},
	]})
	eng.register("减益脉冲", {"units": [
		{"type": U.TINT, "clips": [
			{"frames": 1, "color": Color("ff6666")},
			{"frames": 3, "color": Color.WHITE},
		]},
	]})
	# 回合色（UI 状态与颜色映射）
	eng.register("回合色-我方", {"units": [
		{"type": U.TINT, "clips": [{"frames": 1, "color": TURN_MINE}]}]})
	eng.register("回合色-敌方", {"units": [
		{"type": U.TINT, "clips": [{"frames": 1, "color": TURN_FOE}]}]})
	# 单位退场：**削到最简** —— 只做一次淡出 20 帧 ≈0.33s（迭代032 人明确"不要加那么多东西"）
	#   `trigger_on_stop_call` = 播完才真正移除（迭代030/031 的时序要求）
	eng.register("单位退场", {
		"units": [{"type": U.TINT, "clips": [
			{"frames": 20, "color": Color(1, 1, 1, 0.0)},
		]}],
		"trigger_on_stop_call": "on_unit_fade_out_done",
	})


## 受击抖动定义（弹性衰减 + 围绕原位对称 + 可按数值缩放幅度）
##   · **围绕原位对称**：先算逐段目标位置（递减峰值 0→+A→−A′→…），整段均值≈0
##     （旧实现直接交替 ±振幅并累加，均值不为 0 → 实测偏 +7.3px，整段偏在一侧）
##   · **高伤害延长时长**（伤害≥7：36 → 54 帧），幅度只略升
##   · 段数/幅度带随机（±），**同一实例结果可复现**（按实例播种），不同次抖动各不相同
static func _register_shake(eng: Node, pname: String, base_amp: float, base_frames: int) -> void:
	eng.register(pname, {"units": [], "shake_amp": base_amp, "shake_frames": base_frames})


## 构建一次抖动的 clips（调用方给 value=伤害值；返回 {units, frames}）
static func build_shake(pname: String, value: int, seed_key: int) -> Dictionary:
	var base_amp: float = SHAKE_AMP_MAP if pname == "地图抖动" else SHAKE_AMP_UNIT
	var base_frames: int = SHAKE_FRAMES_MAP if pname == "地图抖动" else SHAKE_FRAMES_UNIT
	# 高伤害延长时长（伤害 >= 7 起）
	var frames: int = base_frames
	var v: int = maxi(1, value)
	if v >= 7:
		var steps_up: int = mini(2, 1 + (v - 7) / 4)
		frames = base_frames + steps_up * SHAKE_FRAMES_BONUS_MAX
	# 段数（约 18 段；带 ±2 随机），每段 2 帧
	var segs: int = 18
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_key
	segs = maxi(6, segs + rng.randi_range(-SHAKE_JITTER_STEPS, SHAKE_JITTER_STEPS))
	var per: int = maxi(1, int(round(float(frames) / float(segs))))
	# 逐段振幅（衰减 0.88，带 ±18% 起伏）；横向抖动
	var amps: Array[float] = []
	var a: float = base_amp * clampf(float(v) / 5.0, 0.6, 1.6)
	for i in segs:
		var jitter: float = 1.0 + rng.randf_range(-SHAKE_JITTER_AMP, SHAKE_JITTER_AMP)
		amps.append(a * jitter)
		a *= SHAKE_DECAY
	# 围绕原位对称：先定逐段"目标偏移"，再换算成 MOVE_BY 的 step（相邻目标之差）
	var targets: Array[Vector2] = []
	for i in segs:
		var sign_ := 1.0 if i % 2 == 0 else -1.0
		targets.append(Vector2(amps[i] * sign_, 0.0))
	var clips: Array = []
	var prev := Vector2.ZERO
	for i in segs:
		clips.append({"frames": per, "step": targets[i] - prev})
		prev = targets[i]
	clips.append({"frames": per, "step": -prev})     # 末段归零 → 无基准位置漂移
	return {"units": [{"type": U.MOVE_BY, "clips": clips}], "frames": frames}


## 飘字：上浮（前 40 帧）+ 淡出（后 20 帧），无前摇
static func _float_pattern() -> Dictionary:
	var rise_frames: int = FLOAT_TEXT_RISE_FRAMES
	var fade_frames: int = maxi(1, FLOAT_TEXT_FRAMES - rise_frames)
	var step: float = FLOAT_TEXT_RISE / float(rise_frames)
	return {
		"units": [
			{"type": U.MOVE_BY, "clips": [
				{"frames": rise_frames, "step": Vector2(0, -step)},
			]},
			{"type": U.TINT, "clips": [
				{"frames": rise_frames, "color": Color(1, 1, 1, 1.0)},
				{"frames": fade_frames, "color": Color(1, 1, 1, 0.0)},
			]},
		],
	}


## 造一个飘字节点（**文字节点**，非图集字形 —— 设计决定 2026-09-17）
static func make_float_label(value: int, kind: String) -> Label:
	var show_v := absi(value)
	var lbl := Label.new()
	lbl.text = str(show_v)
	lbl.add_theme_color_override("font_color", text_color(kind))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.add_theme_font_size_override("font_size", text_size_for(show_v))
	if ResourceLoader.exists(FONT_PATH):
		lbl.add_theme_font_override("font", load(FONT_PATH))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.set_meta("fx_once", true)        ## 播完自释放
	return lbl
