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
