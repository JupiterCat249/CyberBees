# 旧实现存档（已废弃）— 电子蜂 A5（Godot 版）

> 最后更新：2026-09-21
> 状态：**已封存 + 已标注**（历史实现，禁止用作现行实现参考）
> 处置依据：人 2026-09-20 指示「旧实现单独存在新目录并移除引用，标记为废弃」；
> **2026-09-21 追加**：人指示做**废弃代码可达性审计**（判定＝是代码文件 且 从主场景直接/间接都不可达）→ 全量标注（内容移至同名 `.deprecated`、原文件转废弃桩），见 §三 / §五。

---

## 一、这是什么

本目录收纳**已被取代的战斗实现**，保留仅为历史追溯与回滚参考。**现行实现不在这里**：

| 分层 | 现行位置（唯一权威） |
|---|---|
| 规则层（信号驱动 · 零 UI 引用） | `res://scripts/battle/`（11 个 `.gd`） |
| 数据层（Resources 数据类） | `res://scripts/data/`（16 个 `.gd`） |
| 资源层（序列化 `.tres`） | `res://game_data/`（卡牌 / 地图 / 技能 / 效果） |
| 视图层（订阅信号 + 调请求 API） | `res://scenes/ui/arena_view.gd` + `scenes/ui/battle_scene.tscn`（继承 `battle_ui_alpha.tscn`） |

> ⚠️ 规则权威仍是 `电子蜂A5策划案/电子蜂a500规则.md`（边界 T10）；本目录中的规则代码**不代表当前口径**。

---

## 二、存档清单

### 2.1 `scenes_battle/` —— 双节点战斗体系（迭代001–035 实现）

- **原位置**：`res://scenes/battle/`（20 个 `.gd` + 20 个 `.gd.uid`）
- **构成**：协调器 `battle_flow.gd` 位于 `scenes/`（**未移动**，见 §四）· 其下 `battle_state` / `battle_combat` / `battle_turn` /
  `battle_action` / `battle_deploy` / `battle_deck` / `battle_setup` / `battle_victory` / `battle_pending` / `battle_grid` /
  `battle_interaction` / `battle_input` / `battle_defs` / `battle_skills` / `battle_anim` / `battle_bgfx` /
  `battle_board_view` / `battle_hand_view` / `battle_detail_view` / `battle_hud_view`
- **取代者**：`scripts/battle/`（迭代056 新战斗系统）—— 差异是**信号驱动 + UI 完全解耦**（旧体系是节点内互相 `get_node`）
- **仍可用的知识**：`系统维护/战斗节点体系/` 记录了该体系的架构与教训（含重构前代码复盘），**文档保留、代码封存**

### 2.2 `scripts_game/` —— 第一代数据/规则模块（迭代054 实现）

- **原位置**：`res://scripts/game/`（9 个 `.gd` + 9 个 `.gd.uid`）
- **构成**：`game_state` / `board` / `battle_action` / `battle_combat` / `battle_command` / `battle_effects` /
  `action_unit` / `anim_presets` / `battle_anim_driver`
- **取代者**：`scripts/battle/`（规则）+ `scripts/data/`（数据）；迭代056 的 D-3 裁决明确「逻辑层删除重建」
- **注意**：其中 `action_unit.gd` / `anim_presets.gd` / `battle_anim_driver.gd` 是**动画系统**的载体。
  动画系统**尚未接入新引擎**（人已定为后续迭代）—— 存档中的这三个文件是接入工作的**参考实现**，
  但新引擎接入必须走 `scripts/battle/` 的信号层，**不得**直接复用旧节点耦合写法。

---

## 三、受影响与已知破损（如实登记）

| 受影响对象 | 情况 | 处置 |
|---|---|---|
| `project.godot` → `run/main_scene` | 2026-09-21 **已解决**：人已在编辑器里改指 `res://scenes/ui/battle_scene.tscn` → **F5 直接跑当前战斗场景** | ✅ 关闭（原「指向暂时不动」指示已被本次切换取代） |
| `scenes/battle_flow.gd` · `scenes/unuseful_battle_card.tscn` | 旧入口对；主场景切换后已无引用 | **2026-09-21 已标注**：内容移至 `*.deprecated`，原文件转**废弃桩**（`.gd`→纯注释 / `.tscn`→最小空场景） |
| `verification/iter054_*` · `iter055_skill_check.gd` 等 | 用 `preload("res://scripts/game/...")`，**路径已失效** | 属 **T12** 封存验证产物（历史取证），**不随代码演进维护**；如需复跑请改用现行 `scripts/battle/` 入口 |
| Godot 全局类名（`BattleDefs` / `ActionUnit` / `GameState` 等） | 归档 `.gd` 曾被解析 → 其 `class_name` 仍注册进全局类表（副作用：编辑器常驻 37 条旧脚本解析错误） | **2026-09-21 已注销**：归档 `.gd` 全部转桩 → 重扫后**全局类 124 → 115（-9）**，日志噪音随之消失 |
| ⚠️ **`scripts_game/board.gd`（`class_name Board`）** | **承重**：它是**全仓唯一**声明 `Board` 的文件，而生产规则层（`scripts/battle/rules_preview.gd` 等）在用 `Board.ROWS/COLS` —— 归档区里躺着生产依赖 | **2026-09-21 已救出** → 复制进 `scripts/battle/board.gd`（自包含、零 preload），归档原件转桩；生产链路经动画冒烟 **10 PASS / 0 FAIL** 验证 |

---

## 四、为什么 `battle_flow.gd` 留在 `scenes/`

`scenes/battle_flow.gd` 是旧主场景（`scenes/unuseful_battle_card.tscn`）的**协调器**，而 `project.godot` 的
`run/main_scene` 仍指向该场景。人 2026-09-20 明确「**主场景指向暂时不动**」，故：

- 移动 `battle_flow.gd` 会让主场景彻底无法打开（连场景树都加载不了）；
- 保留原位则**至少场景结构可读**，仅动态 `load` 的 11 个模块失效。

> 待日后主场景切换到 `scenes/ui/battle_scene.tscn` 后，`battle_flow.gd` 与
> `scenes/unuseful_battle_card.tscn` 可一并移入本目录，实现「旧入口彻底封存」。

---

## 五、变更记录

| 日期 | 事项 |
|---|---|
| 2026-09-20 | 建档：按人指示将 `scenes/battle/`（20 个）与 `scripts/game/`（9 个）移入 `archive/legacy/`，标记废弃并登记受影响面；`battle_flow.gd` 因主场景未切换而保留原位。 |
| 2026-09-21 | **主场景已切换到 `scenes/ui/battle_scene.tscn`（人操作）→ §四 的"彻底封存"前置条件达成**。按人指示做**可达性审计**（工具 `系统维护/tools/audit_reach.ps1`，覆盖 res:// 字面量 / **UID 引用** / **class_name 全局类** / autoload；动态目录扫描类如 `game_data/**` 明确排除）→ 本目录 28 个 `.gd`（board 除外）与 `scenes/battle_flow.gd`、`scenes/unuseful_battle_card.tscn`、`card-system/**` 共 39 个文件**全量标注**：内容 → `<path>.deprecated`，原文件 → 废弃桩。**⚠️ 同时救出承重类 `Board`**（见 §三）—— 这是本轮审计最重要的发现：*归档区里躺着生产依赖*。全局类 124 → 115。 |
