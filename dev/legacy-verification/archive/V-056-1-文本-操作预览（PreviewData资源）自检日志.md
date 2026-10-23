# 迭代056 操作预览（PreviewData 资源）自检日志（验证用 · 非生产）

> 状态：已封存（验证用，非生产文件）
> 对应迭代：迭代056 · 操作预览资源化
> 封存日期：2026-09-19
> 执行场景：`verification/iter056_preview_check.tscn`

## 一、人指示
> 「完成操作预览（如移动或攻击范围显示），这些东西也做成**资源-供UI调用的资源类**」

## 二、产物
| 文件 | 作用 |
|---|---|
| `scripts/battle/preview_kind.gd` | 预览类型枚举（**独立命名空间**）+ 统一取格入口 |
| `scripts/battle/preview_data.gd` | **PreviewData 资源类**（供 UI 调用） |
| `scripts/battle/rules_preview.gd` | 预览计算（部署/移动/攻击/支援/指令） |
| 总线 `SIG_SELECTION` | 第三个参数改为**承载 PreviewData 资源** |
| 引擎 | `select_support()` + `current_preview()` + `availability_preview()` |

### PreviewData 资源字段（视图读这些）
```
kind   : int              预览类型（PreviewKind.Kind）
cells  : Array            主区域 [{cell: Vector2i, kind: int, primary: bool}]
units  : Array            受影响单位（视图可直接取对象）
caption: String           提示文案
empty  : bool             是否为空
```
便捷方法：`add_cell / add_unit / cells_of / has_cell / grouped / describe`

## 三、自检结果：**28 项全 PASS / 失败 0**
| 组 | 项数 | 内容 |
|---|---|---|
| 资源性 | 6 | 是 Resource；有 kind/cells/units/caption；add_cell/cells_of/has_cell/grouped 正确 |
| 部署预览 | 5 | 兵蜂 = 蜂王相邻空格（3 格，不含蜂王格）；建筑 = 己方领地空格（7 格） |
| 移动预览 | 4 | 走格子；**被单位阻挡**（(1,1) 不可达）；移除阻挡后可达 |
| 攻击预览 | 3 | 射程内命中；射程外排除；**攻击不被单位阻挡** |
| 指令预览 | 2 | 治疗→己方；伤害→敌方 |
| 支援预览 | 3 | 类型 SUPPORT；目标为射程内己方 |
| 引擎信号 | 5 | 开局成功；**信号带出 PreviewData**；预览含部署格；kind=DEPLOY |

## 四、⭐ 本轮捕获并修复的 2 个真实缺陷

| # | 现象 | 真因 | 修法 |
|---|---|---|---|
| 1 | 移动预览把**攻击目标**的格也标成"可移动" | `PreviewData.add_unit()` 用**顶层 kind** 给单位格打标 → 单位预览（kind=MOVE）把攻击目标格也标成 MOVE；于是"被阻挡的 (1,1)"又出现在移动格里 | `add_unit(inst, cell_kind)` **显式声明类型**；三处调用分别传 ATTACK / SUPPORT / COMMAND |
| 2 | 枚举命名空间撞车（**静默出错**） | `PreviewData.Kind` 与 `BattleState.Phase` 值域重叠：`Kind.DEPLOY=1` vs `Phase.DEPLOY=2`、`Kind.ACTION=3` vs `Phase.ACTION=3` → 传错枚举**不报错**，只是取不到格（本轮自检就误判了一条用例） | 枚举**独立成类** `PreviewKind`；视图/测试取格统一走 `PreviewKind.cells_from()`（非法 kind 会**告警**而非静默空） |

> 排查方法记录：先用探针打印 `board.move_range` 与 **逐格 kind**，一眼看出「(1,1) kind=2 primary=true」
> 是攻击目标被误标，而不是移动范围算错 —— **不要靠猜，直接看数据**。

## 五、对 UI 的意义（下一步接视图）
视图拿到 `selection_changed(kind, id, preview, units)` 后：
```
var mv := PreviewKind.cells_from(preview, PreviewKind.Kind.MOVE)     # 移动格
var atk := preview.units                                              # 可攻击目标
```
→ 画格高亮 / 画目标标记，**不需要自己算任何规则**。
