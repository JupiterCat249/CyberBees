extends RefCounted
## 卡牌/单位类型（自 CardData 抽出 —— 迭代083 · B3 第二步）
##
## 为什么要有这个叶子文件：
##   `CardData` 是"卡牌"这一层，而 `EffectData`/`UnitData` 只想知道"什么类型能吃这个效果"。
##   让数据层去认识 CardData 会形成 effect→card→skill→effect 的类型环（迭代074 实测踩过）。
##   抽出本叶子后：谁需要"卡牌类型"就依赖它，不必依赖 CardData。
##
## ⚠️ 兼容性：`CardData` 内部用 `const CardKind := CardKindLib.Kind` 转发，
##   因此 `CardData.CardKind.QUEEN` 这种既有写法（含 verification/ 的封存脚本）**继续可用**。
enum Kind { QUEEN, SOLDIER, BUILDING, COMMAND, COMMAND_X }
