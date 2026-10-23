class_name PreviewKind
extends RefCounted
## 操作预览的**类型枚举**（独立命名空间 · 单一来源）
##
## ⚠️ 为什么单独建类（迭代056 实测教训）
##   `PreviewData.Kind` 原与 `BattleState.Phase` 放在不同类里，两边值域**完全重叠**：
##     Phase: RECOVER=0 TERRAIN=1 DEPLOY=2 ACTION=3
##     Kind : NONE=0 DEPLOY=1 MOVE=2 ATTACK=3 SUPPORT=4 COMMAND=5 DENY=6
##   于是 `Kind.DEPLOY(1)` 与 `Phase.DEPLOY(2)`、`Kind.ACTION(3)` 与 `Phase.ACTION(3)`
##   看起来"同名"却值不同 —— 视图/测试**传错枚举不会编译报错，只会静默取不到格**。
##   （本轮自检就因此误判了一条"移动阻挡"用例。）
##
## 对策：
##   ① 枚举**独立成类**，值域与 Phase 解耦，引用方式统一为 `PreviewKind.XXX`
##   ② 视图所有取格一律走 `PreviewLookup`（本文件的静态方法），**不自己猜值**
##   ③ 取不到时明确返回空数组并（可选）告警，避免"静默空结果"

enum Kind {
	NONE,           ## 无预览
	DEPLOY,         ## 部署可用格（兵蜂：蜂王相邻；建筑：己方领地）
	MOVE,           ## 移动可达格
	ATTACK,         ## 可攻击目标（敌方单位所在格）
	SUPPORT,        ## 支援可作用目标（己方单位所在格）
	COMMAND,        ## 指令卡可作用目标
	DENY,           ## 不可用（点击非法格时的反馈）
}

const ALL := [Kind.NONE, Kind.DEPLOY, Kind.MOVE, Kind.ATTACK, Kind.SUPPORT,
	Kind.COMMAND, Kind.DENY]

const NAME := {
	Kind.NONE: "无",
	Kind.DEPLOY: "部署",
	Kind.MOVE: "移动",
	Kind.ATTACK: "攻击",
	Kind.SUPPORT: "支援",
	Kind.COMMAND: "指令",
	Kind.DENY: "不可用",
}


static func name_of(k: int) -> String:
	return String(NAME.get(k, "未知(%d)" % k))


static func is_valid(k: int) -> bool:
	return ALL.has(k)


## 从预览资源里取某类格的坐标（视图/测试统一入口 —— 不自己写 kind 值）
## 传错 kind 时返回空数组并推一条警告，**不静默**
static func cells_from(preview: Resource, kind: int) -> Array:
	if preview == null:
		return []
	if not is_valid(kind):
		push_warning("PreviewKind.cells_from: kind 非法（%d）—— 是否为 BattleState.Phase？" % kind)
		return []
	return preview.cells_of(kind)
