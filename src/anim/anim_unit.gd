class_name AnimUnit
extends Resource
## Unit（单元）—— 一类动作单元：由若干 Clip **顺序**组成（《动画系统及流程》§一之1、§四之1）
##
## · 5 类 Unit 由 `clips[i].kind` 表达（MOVE_BY / MOVE_TO / ROT_TRACK / TINT / SPAWN_FX）
## · 同一 Pattern 内的多个 Unit **并行**推进（每帧各推一次）——
##   ⚠️ 这是旧实现用实测换来的口径（迭代024：一次只推"当前单元"导致「配置帧 ≠ 实际帧」）
@export var unit_name: String = ""
## 顺序执行的动作列表（静态类型：元素必须是 AnimClip）
@export var clips: Array[AnimClip] = []
## 不可重复：该 Unit 已在同一目标上运行时，不重复起（对应"到指定值 / 追踪"类语义）
@export var unique: bool = false
