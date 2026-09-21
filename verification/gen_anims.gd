extends Node
## 迭代060 动画数据生成器（T12：验证/工具产物；生产代码禁止引用本目录）
##
## 依据：`电子蜂A5策划案/基础动画.md §六 动画清单（实现对照）`
## 口径：手感类参数取**迭代023–028 人实测定稿值**（T14：以实机反馈为准）；§六 未覆盖项按 §六 字面
## 产物：`game_data/anims/*.tres`（一文件一条 Pattern）
##
## ⚠️ **动画时序参数只有这一处定义**（旧实现教训：任何"运行时重新注册"都会把规范悄悄改回去）
## ⚠️ 静态风格要点：`AnimUnit.clips` / `AnimPattern.units` 是**类型化数组**，
##    因此**赋值侧也必须用类型化数组**（`Array[AnimClip]` / `Array[AnimUnit]`），
##    无类型 `Array` 或字面量 `[a, b]` 会报 "Invalid assignment of property 'clips'"。
## 运行：F6 或 project_run(mode="custom", scene="res://verification/gen_anims.tscn")
const DIR: String = "res://game_data/anims"
const ClipLib := preload("res://scripts/anim/anim_clip.gd")
const UnitLib := preload("res://scripts/anim/anim_unit.gd")
const PatternLib := preload("res://scripts/anim/anim_pattern.gd")

# ---- 手感常量（唯一来源，T15：一处可调）----
const SHAKE_FRAMES: int = 40        ## 受击抖动总帧数（迭代023–025 定稿；§六 旧字面值 36）
const SHAKE_SEG_FRAMES: int = 2     ## 每段帧数
const SHAKE_AMP: float = 4.0        ## 基准振幅 px（迭代028 定稿）
const SHAKE_DECAY: float = 0.88     ## 段间衰减（迭代027 定稿）
const SHAKE_JITTER: float = 0.18    ## 振幅 ±%（迭代028 定稿）
const SHAKE_SEED: int = 20260921    ## 固定种子 → 可复现
const SHAKE_THRESHOLD: int = 7      ## 伤害 ≥ 此值 → 延长
const SHAKE_EXTRA: int = 14         ## 延长量（40 → 54 帧）
const EXIT_FRAMES: int = 20         ## 单位退场（迭代032 定稿：仅一次淡出）
const FLOAT_RISE: int = 40          ## 飘字上浮帧数
const FLOAT_FADE: int = 20          ## 飘字淡出帧数
const MAP_SHAKE_FRAMES: int = 54    ## 地图抖动总帧数（§六：54 帧 0.90s；《动画系统及流程》§二之2）
const MAP_SHAKE_SEG: int = 3        ## 每段帧数（18 段 × 3 = 54）
const MAP_SHAKE_AMP: float = 7.0    ## 基准振幅 px（§六）

var _saved: int = 0
var _failed: int = 0


func _ready() -> void:
	print("=== 迭代060 动画数据生成 ===")
	DirAccess.make_dir_recursive_absolute(DIR)
	_gen_shake()
	_gen_flash_red()
	_gen_card_enter()
	_gen_card_exit()
	_gen_deploy_land()
	_gen_move_land()
	_gen_unit_exit()
	_gen_cast_flash()
	_gen_buff_pulse(true)
	_gen_buff_pulse(false)
	_gen_float_text()
	_gen_map_shake()
	_gen_turn_color(true)
	_gen_turn_color(false)
	print("=== 结果：%d 已生成 / %d 失败 ===" % [_saved, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


# ============================================================
#  构件工厂
# ============================================================

func _clip(kind: int, frames: int, off: Vector2 = Vector2.ZERO, tint: Color = Color(1, 1, 1, 1)) -> AnimClip:
	var c := ClipLib.new()
	c.kind = kind
	c.frames = frames
	c.offset = off
	c.tint = tint
	return c


func _unit(unit_name: String, clips: Array[AnimClip]) -> AnimUnit:
	var u := UnitLib.new()
	u.unit_name = unit_name
	u.clips = clips
	return u


func _pattern(pattern_name: String, units: Array[AnimUnit]) -> AnimPattern:
	var p := PatternLib.new()
	p.pattern_name = pattern_name
	p.units = units
	return p


func _save(p: AnimPattern) -> void:
	var path: String = "%s/%s.tres" % [DIR, p.pattern_name]
	var err: int = ResourceSaver.save(p, path)
	if err == OK:
		_saved += 1
		print("  OK    %s（%d 单元）" % [path, p.units.size()])
	else:
		_failed += 1
		print("  FAIL  %s（err=%d）" % [path, err])


func _units1(u: AnimUnit) -> Array[AnimUnit]:
	var a: Array[AnimUnit] = [u]
	return a


# ============================================================
#  ① 受击抖动（§六：36 帧 0.60s · 18 段 ±2 · 基准 4px；伤害 ≥7 延长）
#    定稿：40 帧 · 段长 2 帧 · 衰减 0.88 · 振幅 ±18% · 起始方向随机（固定种子）
#    ⚠️ 必须**围绕原位对称**（迭代027：末帧归零，否则会"先右移再跳回"）
# ============================================================
func _gen_shake() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SHAKE_SEED
	var segs: int = SHAKE_FRAMES / SHAKE_SEG_FRAMES
	var dir: float = 1.0 if rng.randf() < 0.5 else -1.0
	var clips: Array[AnimClip] = []
	var run: float = 0.0
	for k: int in range(segs - 1):
		var a: float = SHAKE_AMP * pow(SHAKE_DECAY, float(k)) * (1.0 + rng.randf_range(-SHAKE_JITTER, SHAKE_JITTER))
		var off: float = a * dir
		run += off
		clips.append(_clip(ClipLib.Kind.MOVE_BY, SHAKE_SEG_FRAMES, Vector2(off, 0)))
		dir = -dir
	clips.append(_clip(ClipLib.Kind.MOVE_BY, SHAKE_SEG_FRAMES, Vector2(-run, 0)))
	var p: AnimPattern = _pattern("受击抖动", _units1(_unit("左右往复", clips)))
	p.value_ref = 4
	p.value_threshold = SHAKE_THRESHOLD
	p.extra_frames = SHAKE_EXTRA
	_save(p)


# ------------------------------------------------------------
#  ② 受伤闪红（§六：6 帧 · #FF2000 → 橙 → 白）
func _gen_flash_red() -> void:
	var clips: Array[AnimClip] = []
	clips.append(_clip(ClipLib.Kind.TINT, 2, Vector2.ZERO, Color("#FF2000")))
	clips.append(_clip(ClipLib.Kind.TINT, 2, Vector2.ZERO, Color("#FF8800")))
	clips.append(_clip(ClipLib.Kind.TINT, 2, Vector2.ZERO, Color(1, 1, 1, 1)))
	_save(_pattern("受伤闪红", _units1(_unit("变色", clips))))


# ------------------------------------------------------------
#  ③ 卡牌登场（§六：1 + 4 帧 · 第 1 帧即到位，仅淡入）
func _gen_card_enter() -> void:
	var clips: Array[AnimClip] = []
	var steps: int = 5
	for i: int in range(steps):
		clips.append(_clip(ClipLib.Kind.TINT, 1, Vector2.ZERO, Color(1, 1, 1, float(i) / float(steps - 1))))
	_save(_pattern("卡牌登场", _units1(_unit("淡入", clips))))


# ------------------------------------------------------------
#  ④ 卡牌退场（§六：3 + 2 帧 · 无后摇，末帧即消失）
func _gen_card_exit() -> void:
	var clips: Array[AnimClip] = []
	clips.append(_clip(ClipLib.Kind.TINT, 3, Vector2.ZERO, Color("#FF3333")))
	clips.append(_clip(ClipLib.Kind.TINT, 2, Vector2.ZERO, Color(1, 1, 1, 0)))
	_save(_pattern("卡牌退场", _units1(_unit("偏红→消失", clips))))


# ------------------------------------------------------------
#  ⑤ 部署落位（§六：1 帧下沉 + 回弹；瞬时动作、无前摇）
func _gen_deploy_land() -> void:
	var clips: Array[AnimClip] = []
	clips.append(_clip(ClipLib.Kind.MOVE_BY, 1, Vector2(0, 3)))
	clips.append(_clip(ClipLib.Kind.MOVE_BY, 1, Vector2(0, -3)))
	_save(_pattern("部署落位", _units1(_unit("下沉回弹", clips))))


# ------------------------------------------------------------
#  ⑥ 移动落位（§六：2 帧 仅纵向 (0,3)→(0,-3)；迭代026 起无左右位移）
func _gen_move_land() -> void:
	var clips: Array[AnimClip] = []
	clips.append(_clip(ClipLib.Kind.MOVE_BY, 1, Vector2(0, 3)))
	clips.append(_clip(ClipLib.Kind.MOVE_BY, 1, Vector2(0, -3)))
	_save(_pattern("移动落位", _units1(_unit("下沉回弹", clips))))


# ------------------------------------------------------------
#  ⑦ 单位退场（§六：20 帧 · 仅一次淡出；迭代032：去掉偏红染色与上浮位移）
func _gen_unit_exit() -> void:
	var clips: Array[AnimClip] = []
	for i: int in range(EXIT_FRAMES):
		var a: float = 1.0 - float(i + 1) / float(EXIT_FRAMES)
		clips.append(_clip(ClipLib.Kind.TINT, 1, Vector2.ZERO, Color(1, 1, 1, a)))
	_save(_pattern("单位退场", _units1(_unit("淡出", clips))))


# ------------------------------------------------------------
#  ⑧ 施放闪白（§六：瞬时）
func _gen_cast_flash() -> void:
	var clips: Array[AnimClip] = []
	clips.append(_clip(ClipLib.Kind.TINT, 1, Vector2.ZERO, Color(1, 1, 1, 1)))
	_save(_pattern("施放闪白", _units1(_unit("闪白", clips))))


# ------------------------------------------------------------
#  ⑨ 增益 / 减益脉冲（§六：瞬时 · 与数值文本同帧）
func _gen_buff_pulse(is_buff: bool) -> void:
	var nm: String = "增益脉冲" if is_buff else "减益脉冲"
	var col: Color = Color("#7CFFB0") if is_buff else Color("#FF8A6A")
	var clips: Array[AnimClip] = []
	clips.append(_clip(ClipLib.Kind.TINT, 1, Vector2.ZERO, col))
	_save(_pattern(nm, _units1(_unit("脉冲", clips))))


# ------------------------------------------------------------
#  ⑩ 浮字上浮（§六：60 帧 · 上浮 40（递减步长）+ 淡出 20）
func _gen_float_text() -> void:
	var rise: Array[AnimClip] = []
	for i: int in range(FLOAT_RISE):
		var k: float = 1.0 - float(i) / float(FLOAT_RISE)
		rise.append(_clip(ClipLib.Kind.MOVE_BY, 1, Vector2(0, -2.0 * k)))
	var fade: Array[AnimClip] = []
	for i: int in range(FLOAT_RISE):
		fade.append(_clip(ClipLib.Kind.TINT, 1, Vector2.ZERO, Color(1, 1, 1, 1)))
	for i: int in range(FLOAT_FADE):
		var a: float = 1.0 - float(i + 1) / float(FLOAT_FADE)
		fade.append(_clip(ClipLib.Kind.TINT, 1, Vector2.ZERO, Color(1, 1, 1, a)))
	var units: Array[AnimUnit] = []
	units.append(_unit("上浮", rise))
	units.append(_unit("淡出", fade))
	_save(_pattern("浮字上浮", units))


# ------------------------------------------------------------
#  ⑪ 地图抖动（《动画系统及流程》§二之2：「释放攻击 AOE 时整个地图/镜头抖动」
#     §六：54 帧 0.90s · 18 段 ±2 · 基准 7px）
#     同受击抖动：围绕原位对称、逐段衰减、末段抵消归零
func _gen_map_shake() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SHAKE_SEED + 1
	var segs: int = MAP_SHAKE_FRAMES / MAP_SHAKE_SEG
	var dir: float = 1.0 if rng.randf() < 0.5 else -1.0
	var clips: Array[AnimClip] = []
	var run: float = 0.0
	for k: int in range(segs - 1):
		var a: float = MAP_SHAKE_AMP * pow(SHAKE_DECAY, float(k)) * (1.0 + rng.randf_range(-SHAKE_JITTER, SHAKE_JITTER))
		var off: float = a * dir
		run += off
		clips.append(_clip(ClipLib.Kind.MOVE_BY, MAP_SHAKE_SEG, Vector2(off, 0)))
		dir = -dir
	clips.append(_clip(ClipLib.Kind.MOVE_BY, MAP_SHAKE_SEG, Vector2(-run, 0)))
	_save(_pattern("地图抖动", _units1(_unit("地图左右往复", clips))))


# ------------------------------------------------------------
#  ⑫ 回合色（《动画系统及流程》§二之3；§六：1 帧硬切）
#     我方 `#499169` / 敌方 `#A84331`；实现＝对目标做 1 帧 TINT（modulate 乘色）
func _gen_turn_color(is_ally: bool) -> void:
	var nm: String = "回合色-我方" if is_ally else "回合色-敌方"
	var col: Color = Color("#499169") if is_ally else Color("#A84331")
	var clips: Array[AnimClip] = []
	clips.append(_clip(ClipLib.Kind.TINT, 1, Vector2.ZERO, col))
	_save(_pattern(nm, _units1(_unit("硬切", clips))))
