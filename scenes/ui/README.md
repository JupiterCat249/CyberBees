# UI 场景结构（电子蜂 A5 · Godot 版）

> 最后更新：2026-09-24
> 依据：`电子蜂A5策划案/Figma设计/电子蜂对战空间 (1)/横版UI填充.svg`（**最高标准**）
>      + `电子蜂A5策划案/电子蜂A5策划案.md` §六 UI（补充）
> **2026-09-20 修订**：场景清单按真实文件重列（旧清单列的 `menu_main.tscn` / `level_battle.tscn` **已不存在**）；补充现行战斗入口与旧实现废弃说明。
> **2026-09-24 修订（文档收口轮）**：**主场景口径裁决** —— `run/main_scene` 已是 `scenes/ui/battle_scene.tscn`（旧记「仍指向 `unuseful_battle_card.tscn` · 暂不动」作废）；补登迭代062 的**联机大厅**与迭代063 的**结算浮层**。

## 现行入口（重要）

| 入口 | 场景 | 说明 |
|---|---|---|
| **战斗（现行 · = `run/main_scene`）** | `scenes/ui/battle_scene.tscn` | 继承 `battle_ui_alpha.tscn` + 挂 `arena_view.gd`（视图适配器）；**F5 主场景运行即此场景**（亦可 F6） |
| **联机大厅（迭代062）** | `scenes/ui/net_lobby.tscn` | 人数 + 匹配按钮 → 配对后切 `battle_scene`；**用 F6 单独运行**；档位由 `net_config/profile.flag`（`test`/`prod`）决定，默认档见 `net_config/net.*.json` |
| ⚠️ 旧入口（已废弃） | `scenes/unuseful_battle_card.tscn` + `scenes/battle_flow.gd` | **已转 `.deprecated` 桩**（迭代060），`run/main_scene` **已不再指向**；其依赖的 `scenes/battle/*` 已移入 `archive/legacy/scenes_battle/`，**动态加载已断开** |

## 场景清单（真实文件）

| 场景 | 用途 | 脚本 |
|---|---|---|
| `battle_scene.tscn` | **现行组合战斗场景**（继承底座 + 视图适配 · = `run/main_scene`） | `arena_view.gd` |
| `battle_ui_alpha.tscn` | **战斗 UI 底座**（人手工版 · 59+ 节点 · 编辑器可直改） | — |
| `net_lobby.tscn` | **联机大厅**（迭代062：在线/匹配中/对局中人数 + 匹配按钮） | `net_lobby.gd` |
| `card_unit.tscn` | 地图单位卡（可复用素材场景 · 250×250） | `card_unit.gd` |
| `card_hand.tscn` | 手牌卡（可复用素材场景 · 200×200） | `card_hand.gd` |
| `float_text.tscn` | 飘字层（迭代060 · **运行时挂 `$HUD`**，不再改主场景 `.tscn`） | — |
| `cost_badge.tscn` | 费用徽章 | — |
| `crt_fx_general.tscn` | 显像管特效（通用） | — |
| `board_cell.gd` | 棋盘格（非场景：运行时由 `arena_view.gd` 挂到格子） | `board_cell.gd` |
| `result_panel.gd` | **结算浮层**（迭代063 · **代码构建，不落场景**避开编辑器回退坑） | `result_panel.gd` |

> 现行运行时结构：`arena_view.gd` 订阅 `BattleSignalBus` 的 15 类信号驱动上述场景；点击事件按预览资源的 `kind`
> 翻译成 `BattleEngine.request_*` 请求（**视图不自行判定规则**）；联机时再经 `scripts/net/net_intent.gd`（**op 唯一转换点**）上行。
> ⚠️ 代码构建 UI 在 `CanvasLayer` 下**锚点无参照**，须显式给视口尺寸（迭代063 踩坑）。

## 组件构成（取自填充稿实测 · 仍有效）

**地图单位卡 250×250**
- 本体 `rx10`（底色=卡牌类型：单位 `#FFFFFF` / 蜂王 `#FFD07E` / 建筑 `#DDC29B` / 指令 `#D9D9D9`）
- 左右侧边栏 `40×250`（阵营色：我方 `#3B816D` / 敌方 `#A84331`）
- 立绘区 `155.83×233` @(47,8)　·　费用格 `40×40` `#353535` @(0,0)
- 内描边 `248×248 rx9` @(1,1) `#000000-20%`
- 四维：`40×40` 数值格（白 80%）+ `40×40` 图标格；左列 攻击/血量 @y65/105，右列 移动/射程 @y160/200

**手牌卡 200×200**
- 本体 `rx10`（同上类型底色）· 插画 `180×180` @(10,10)
- 费用块 `23×33` 白 @(+2,+18) · 内描边 `196×196 rx8` @(2,2) `#333333` 4px
- 卡槽位置：左 (30,150)(230,150)(30,350)(230,350)；右 (1490,150)(1690,150)(1490,350)(1690,350)

## 待接素材

- **地形格图标**：`TerrainEffect.icon` 现为空（地形格只画叠加色 + 描边）—— 素材到位后按资源挂载即可，无需改代码。
- **地图贴图**：6 张图现共用同一张贴图；分图素材到位后经 `ArenaAssets.map_texture` + `SIG_MAP_ASSETS` 下发。
- 素材库参考：`电子蜂A5策划案/素材/zip原图/`（卡牌a-金刚蜂王 / 卡牌c1-泥蜂 / 卡牌c2-熊蜂 / 卡牌d1-电击 …）

## ⚠️ 已知失效引用（勿照抄）

| 位置 | 情况 |
|---|---|
| 本文件旧版列的 `menu_main.tscn` / `level_battle.tscn` | **已不存在**（页面流转方案未落地，现行战斗为单场景） |
| `tools/*.tscn`（`ui_probe` / `ui_screenshot` / `fx_only` / `perf_probe` 等） | 取证工具链，部分仍引用旧场景/旧路径 —— 属工具，不属生产路径；复跑前需先核对路径 |
| 旧组件规格文档中提到的 `level_battle.load_map()/spawn_unit()` | 属旧入口 API，现行接口为 `arena_view.gd` + `BattleEngine.request_*` |
