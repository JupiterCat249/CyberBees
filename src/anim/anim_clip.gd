class_name AnimClip
extends Resource
## Clip（动作）—— 动画系统最小单元（《电子蜂A5策划案/动画系统及流程.md》§一之1）
##
## 数据驱动：全部由 `.tres` 承载（`game_data/anims/`）；**代码里不得硬编码任何时序**。
## ⚠️ T2：时长一律用**帧数**表达（不用秒、不用 delta）。
enum Kind {
	MOVE_BY,   ## 移动/旋转**指定数值** —— **可叠加**（每帧 += offset / += rotation_step）
	MOVE_TO,   ## 移动/旋转**到指定数值** —— 不可重复（frames 帧内线性到位）
	ROT_TRACK, ## 旋转**追踪目标** —— 不可重复（朝向 track_node）
	TINT,      ## **变色** —— 设置 modulate
	SPAWN_FX,  ## **生成特效** —— 在目标处实例化 fx_scene
}

## 规则2 的条件（§一之4 line 27：任意动作可跳转/触发/终止，**支持条件判断**）
enum Cond {
	NONE,      ## 无条件（恒真）
	VALUE_GTE, ## 本次动画的 value ≥ cond_value
	VALUE_LT,  ## 本次动画的 value < cond_value
}

@export var kind: Kind = Kind.MOVE_BY
## 持续帧数（1 帧 = 瞬时动作）
@export var frames: int = 1
## MOVE_BY：每帧位移增量；MOVE_TO：相对**动画起点**的目标位移
@export var offset: Vector2 = Vector2.ZERO
## MOVE_BY：每帧旋转增量（弧度）；MOVE_TO：相对起点的目标旋转
@export var rotation_step: float = 0.0
## ROT_TRACK：被追踪节点（相对目标节点的父节点解析）
@export var track_node: NodePath = NodePath()
## TINT：目标颜色（**绝对值**，白色 = 复原）
@export var tint: Color = Color(1, 1, 1, 1)
## SPAWN_FX：要实例化的特效场景
@export var fx_scene: PackedScene = null

# ------------------------------------------------------------
#  规则2（§一之4 line 27）：本 Clip **开始时**可跳转 / 触发 / 终止其他单元或动画
#  由 `condition` 门控；三项均为数据字段（非脚本语言）
# ------------------------------------------------------------
@export var condition: Cond = Cond.NONE
@export var cond_value: int = 0
## 本 Clip 开始时**触发**的 Pattern 名（空 = 不触发）
@export var on_start_trigger: String = ""
## 本 Clip 开始时**终止**的 Pattern 名（空 = 不终止）
@export var on_start_stop: String = ""
## 本 Clip 开始时**跳转**到本 Pattern 的第 N 个 Unit（-1 = 不跳转）
##   ⚠️ 语义：**只能向后跳**（N > 当前单元下标）—— 从前向后跳以杆绝自跳死循环
@export var on_start_goto_unit: int = -1
