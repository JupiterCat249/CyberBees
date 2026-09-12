# V-004-9 迭代004 · 步骤5/6 **运行时验证通过** + `turn_color` 崩溃修复 · 取证

> 状态：已封存（验证用，非生产文件）
> 对应迭代·检查点：迭代004 · 步骤5（数值文本）/ 步骤6（UI 回合色）运行时验证
> 封存日期：2026-08-27

## ⚠️ 本轮抓到并修复一个**真实运行时崩溃**

启动时游戏**停在调试器断点** ✗：
```
_on_state_changed: Invalid call. Nonexistent function 'turn_color' in base 'Node (battle_anim.gd)'
  battle_hud_view.gd:55 @ _on_state_changed()  ← battle_state.gd:627 refresh() ← battle_flow.gd:184 _ready()
```

**根因**：落地"7 条默认 Pattern"时，我**只加了颜色常量 `TURN_MINE/TURN_FOE`，漏加了 `turn_color()` 函数** ✗
（当时该函数的版本在被打断的那次补丁里，重写时丢了）→ 步骤6 的 HUD 调用它即崩 ✗。

**为什么上一轮的"编译无诊断 + 启动 live"没发现**：编译期无法发现"Node 上不存在的动态方法调用"；
而上一轮启动显示 live 是在**改动生效前**的旧实例（`was_already_running` 语义）✗。
→ **教训：跨文件调用引擎新 API 后，必须做一次"重启 + 运行时读值"，不能只看编译与首次启动**。

**修复**：
```gdscript
const NEUTRAL_COLOR := Color(1, 1, 1, 0.5)   ## #FFFFFF-50%（中性/结束态）
func turn_color(is_mine: bool) -> Color:
	return TURN_MINE if is_mine else TURN_FOE
```

## 运行时验证（修复后，实机 eval 只读）

| 项 | 结果 |
|----|------|
| `state.anim` | `true` ✅ |
| `text_color("damage"/"refund"/"heal")` | `ff2000` / `ffa300` / `00dd00` —— **与表现规范逐项一致** ✅ |
| `turn_color(true/false)` | `499169` / `a84331` ✅ |
| 中性色（结束态） | `#FFFFFF` + alpha 0.5 = **`#FFFFFF-50%`** ✅ |
| `text_size_for(1/3/5/9)` | `44 / 52 / 60 / 72` —— **字号随数值** ✅ |
| 游戏运行 | 正常（`phase=0 current=green`，**不再崩溃**）✅ |

## 迭代004 剩余

| 项 | 说明 |
|----|------|
| 4c | **受击/AOE/登场 的视觉取证**：真实鼠标走 开始对局→部署→行动→攻击 + `pilot_screenshot`/`read_image`（T13 的 `reviewed: true`）|
| 5b | **AOE 地图抖动接入**：`state.anim.shake_map()` 在技能命中多目标（溅射/链式）处调用 |
| 7 | 迭代004 验收结论 + tag `iter/004` |
