extends RefCounted
## 阶段文案与颜色（自 arena_view 切出 —— 迭代088 · B5 第十一刀）
##
## ⚠️ 人裁定的两条口径原样保留：
##   · 「橙色提示文本省略」→ 阶段提示只走**控制台输出**（`flash` 回调），不占界面；
##   · 信息面板右下角显示**地图机制**（由 map_assets 填），此处**不得覆写** `SiteEffect`。

const PHASE_RECOVER := 0
const PHASE_TERRAIN := 1


## 阶段开始：播报阶段名 + 操作提示（控制台）
static func announce(is_ally: bool, phase: int, flash: Callable) -> void:
	## 阶段文本 + 操作提示（迭代058：可发现性 —— 告诉玩家「现在能做什么」）
	var names := {0: "回费", 1: "场地", 2: "部署", 3: "行动"}
	var tips := {
		0: "自动结算：己方单位回费 + 行动机会重置",
		1: "自动结算：场地效果作用于格子上的单位",
		2: "部署阶段：点手牌部署单位/使用指令，准备好后点右侧按钮进入行动阶段",
		3: "行动阶段：点自己的单位可移动/攻击/支援（每单位每回合 1 次行动）",
	}
	## ⚠️ 迭代064 B7（人 2026-09-27 清单 UI-6）：信息面板显示的是**地图机制**，
	##   已由 map_assets 填入 `ArenaAssets.map_desc` ⇒ 此处**不覆写 SiteEffect**，阶段提示走控制台。
	flash.call("%s阶段（%s）｜%s" % [
		str(names.get(phase, "?")), "绿" if is_ally else "红", str(tips.get(phase, ""))])


## 阶段文本颜色（§二之3：结束部署/行动 = 白；回费·场地阶段 = 白 50%）
static func tint(root: Node, phase: int) -> void:
	var lb := root.get_node_or_null("HUD/ActionBar/Label") as Label
	if lb == null:
		return
	lb.modulate = Color(1, 1, 1, 0.5) if (phase == PHASE_RECOVER or phase == PHASE_TERRAIN) \
		else Color(1, 1, 1, 1)
