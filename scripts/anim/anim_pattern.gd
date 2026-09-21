class_name AnimPattern
extends Resource
## Pattern（动画）—— 由若干 Unit 组成（《动画系统及流程》§一之1、§一之2）
##
## 生命周期（§一之2）：`ResetUnit`（渲染时自动初始化）· `Action`（开始）· `Stop`（终止，**不复位**）
## 分支触发（§一之2）：开始时触发 / 终止时触发另一 Pattern
## 运行选项（§一之4）：运行时禁 UI 交互 · 是否受全局暂停影响
##
## 数据驱动：一条 Pattern = 一个 `.tres`（`game_data/anims/`），**新增动画不改代码**
## 注：`units` 用无类型 Array（同 AnimUnit 的说明）；元素必须是 AnimUnit。
@export var pattern_name: String = ""
@export var units: Array = []
## 动画**开始时**触发的 Pattern 名（空 = 不触发）
@export var trigger_on_start: String = ""
## 动画**终止时**触发的 Pattern 名（空 = 不触发）
@export var trigger_on_stop: String = ""
## 运行时禁 UI 交互（收尾自动复位）
@export var block_ui: bool = false
## 是否受全局暂停影响（false = 常驻，如"常驻呼吸"）
@export var pause_global: bool = true
## 数值缩放基准：>0 时 MOVE_BY 的 offset 按 `value / value_ref` 缩放（0 = 不缩放）
@export var value_ref: int = 0
## 条件延长：`value >= value_threshold` 时，各 Unit 的**末个 Clip** 加 `extra_frames` 帧
@export var value_threshold: int = 0
@export var extra_frames: int = 0
