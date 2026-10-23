extends RefCounted
## 玩家信息面板的**压暗口径**（自 arena_view._info_tint 切出 —— 迭代132）
##
## 现行口径（人 2026-10-14 重定）：**按行动方对称** —— 该侧是行动方 ⇒ 全白；否则一律变黑。
##   ⇒ 同一时刻两端看到同一规律：行动那侧亮、另一侧黑。
##
## ⚠️ 沿革（勿据旧注释回改）：本条曾是「我方→灰 0.65 / 敌方→黑 0.22」的非对称三态，
##   2026-10-10 曾判定"不应改成对称"并逐字还原；2026-10-14 人重新指示改为对称。

const NORMAL := Color(1, 1, 1, 1)
const BLACK := Color(0.22, 0.22, 0.22, 1)


## active = 当前行动方；side = 该面板代表的阵营
static func filter_for(active: int, side: int) -> Color:
	return NORMAL if int(active) == int(side) else BLACK
