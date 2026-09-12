# V-004-1 迭代004 · 自写 Action Unit 动画引擎（引擎层） · 验证取证

> 状态：已封存（验证用，非生产文件）
> 对应迭代·检查点：**迭代004（统一动画系统）· 第1步 引擎层**
> 封存日期：2026-08-27

## 交付：`scenes/battle/battle_anim.gd`（~210 行，`extends Node`）

**严格遵守边界**：
- **T3**：**不使用** AnimationPlayer / Tween / AnimationTree —— 全部逐帧自算 ✅
- **T2**：**不使用 delta** —— `_process` 只做逐帧步进，时长以**帧数**计 ✅

### 忠实实现策划案「一、动画系统架构」

| 策划案条目 | 实现 |
|-----------|------|
| 层级 `Pattern → Unit → Clip` | `_patterns[名] = {units:[{type, clips:[…]}]}`；`_step()` 按 单元→动作 顺序推进 |
| `ResetUnit`（渲染时自动初始化） | `reset_unit()` / `action()` 内部先 `_apply_initial()`（恢复 `inited` 声明字段）|
| `Action`（开始） | `action(名, 目标)`：重置→入运行表→按定义触发 `trigger_on_start` |
| `Stop`（终止） | `stop(名)`：移出运行表→按定义触发 `trigger_on_stop` |
| 分支与触发（A 触发 B） | `trigger_on_start`（A 开始时触发）/ `trigger_on_stop`（终止 A 时触发）|
| **5 类 Unit** | `enum U { MOVE_BY, MOVE_TO, ROT_TRACK, TINT, SPAWN_FX }` —— 分别对应"指定值可叠加 / 到指定值不可重复 / 旋转追踪 / 变色 / 生成特效" |
| 规则①顺序执行 | `_step()`：动作1→动作2→动作3，单元内完成后自动进入下一单元 |
| 规则②可跳转/触发/终止 | 触发见上；`stop()` 可被随时调用 |
| 规则③**终止级联且不复位** | `stop()` 直接移出运行表，**不恢复 `inited`**（注释明确标注）|
| 规则④禁 UI 交互 / 受全局暂停 | `ui_locked`（`block_ui` 的 Pattern 自动上/解锁）· `anim_paused` + 每 Pattern 的 `pause_global` |

### 关键 API

```gdscript
register(name, spec)          # 注册 Pattern
action(name, target)          # 开始（ResetUnit + 触发 on_start + 锁 UI）
reset_unit(name, target)      # 重置（渲染时初始化）
stop(name) / stop_all()       # 终止（级联、不复位、可触发 on_stop）
has_pattern / pattern_names / is_running / running_names
ui_locked · anim_paused · fx_parent   # 全局开关与特效挂载点
```

## 待完成（迭代004 后续步骤）

| 步 | 内容 |
|----|------|
| 2 | **清理 T3 违规残留**：`battle_card.tscn` 的 `AnimationPlayer`(ScanAnim) + `Animation`/`AnimationLibrary` 子资源 |
| 3 | 在 `battle_flow` 注入 `state.anim`（作 Node 挂到 Battle 下）+ 起始自检项 +1 |
| 4 | 定义默认 Pattern：单位受击抖动 · AOE 地图抖动 · 卡牌登场/退场 · 变色（回合色/受伤色）|
| 5 | 数值文本：回费 `#FFA300` / 受伤 `#FF2000` / 回血 `#00DD00`，**字号随数值**；六个瞬间动作**无前摇** |
| 6 | UI 回合色：我方 `#499169` / 敌方 `#A84331` / `#FFFFFF-50%` |
| 7 | 实机验证（真实鼠标）+ T13 封存 + 系统维护建档（基础描述/API/扩展-如何新增动画）+ 迭代验收 + tag |
