extends Control
## ============================================================
## 战斗 UI 根控制器（场景格式 UI · 迭代037）
##
## 架构（按人明确要求）：
##   · **UI 由节点构成** —— 视觉全在 `ui_battle_index.tscn` 与子场景里，
##     可在编辑器中直接摆放/编辑，**无需运行即可看到效果**。
##   · **节点靠信号通信** —— 子场景各自发信号（`ui_unit_card.gd`），
##     在场景文件的 `[connection]` 段连到本控制器；本控制器只做**路由**。
##   · **代码极简** —— 只做"信号转发"，不创建节点、不操作子节点内部视觉。
##
## 目标：替代 card-system 的"单 shader 自绘"方案（无法可视化编辑）。
## ============================================================

## 对外信号（供上层游戏逻辑连接）
signal deploy_confirmed()           ## 主按钮：确认部署
signal card_selected(id: int)       ## 单位卡：被点击
signal unit_cards_ready(count: int) ## 地图单位卡已就绪


func _ready() -> void:
	# 卡片由场景实例化（见 .tscn 的 instance=...），此处只广播就绪事件
	var layer: Control = $UnitCards
	unit_cards_ready.emit(layer.get_child_count())


## —— 信号处理（由 .tscn 的 [connection] 段驱动）——

func _on_main_button_pressed() -> void:
	deploy_confirmed.emit()


func _on_unit_card_pressed(id: int) -> void:
	card_selected.emit(id)


## 绑定一组单位卡数据（上层调用；卡片内部结构不变，只换值）
func bind_unit_cards(cards: Array) -> void:
	var children: Array = $UnitCards.get_children()
	for i in mini(children.size(), cards.size()):
		var c: Node = children[i]
		if c.has_method("bind"):
			c.call("bind", cards[i])
