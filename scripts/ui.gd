extends Control
## UI 层：监听全局 GameState(Autoload) 信号，更新 回合/阶段/费用/手牌/交互提示，渲染手牌区，显示胜负。

@onready var hand_box: HBoxContainer = $Hand

func update_status() -> void:
	var label: Label = $StatusLabel
	var phase_name: String = ["回费", "部署", "行动"][GameState.phase]
	var hint := ""
	if GameState.mode == GameState.IMode.DEPLOY:
		hint = "  [点绿格放置兵蜂]"
	elif GameState.mode == GameState.IMode.UNIT_ACTION:
		hint = "  [点高亮格移动/点敌人攻击]"
	else:
		hint = "  [点兵蜂卡部署; 点己方单位行动; 结束回合]"
	label.text = "回合%d [%s] 费用%d/%d 手牌%d%s" % [GameState.turn_number, phase_name, GameState.cost, GameState.MAX_COST, GameState.hand.size(), hint]
	_refresh_hand()


func show_game_over(winner: String) -> void:
	$StatusLabel.text = "游戏结束: %s 获胜" % winner


func _refresh_hand() -> void:
	for child in hand_box.get_children():
		child.queue_free()
	for i in GameState.hand.size():
		var card: Dictionary = GameState.hand[i]
		var btn := Button.new()
		btn.text = "%s(%d)" % [card["name"], card["cost"]]
		btn.custom_minimum_size = Vector2(104, 40)
		btn.pressed.connect(_on_card_pressed.bind(i))
		hand_box.add_child(btn)


func _on_card_pressed(index: int) -> void:
	GameState.select_card(index)
