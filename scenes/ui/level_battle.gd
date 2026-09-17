extends Control
## 战斗关卡：自包含单元（背景/棋盘/手牌/单位/玩家状态/HUD）
## 最小代码原则 —— 只做节点做不到的事：① 内容绑定 ② 页面跳转
## 未来适配：地图切换改 map_name/terrain_texture 并调 load_map()；返回主菜单走 back_to_menu()

@export var map_name := "丰饶"
@export var turn_text := "回合6--先手"
@export var site_effect := "场地效果：第3、9回合玩家额外回复4点费用"
@export var enemy_name := "Nemo"
@export var player_name := "Jupiter"

func _ready() -> void:
	apply_content()

## 内容绑定入口（改地图/改文案只调这里，不散落各处）
func apply_content() -> void:
	$MatchInfo/MapName.text = map_name
	$MatchInfo/TurnInfo.text = turn_text
	$MatchInfo/SiteEffect.text = site_effect
	$SideEnemy/Name.text = enemy_name
	$Name.text = player_name

## 换地图：改名字 + 换棋盘贴图（预置多张地图时按名切换即可）
func load_map(p_map_name: String, p_terrain: Texture2D) -> void:
	map_name = p_map_name
	$Board/Terrain.texture = p_terrain
	apply_content()

## 挂单位卡：复用 card_unit.tscn（units_parent 传 $Board/Units）
func spawn_unit(scene: PackedScene, cell_x: int, cell_y: int, data: Dictionary) -> Node:
	var card: Node = scene.instantiate()
	card.position = Vector2(cell_x * 250, cell_y * 250)
	$Board/Units.add_child(card)
	if card.has_method("bind"):
		card.call("bind", data)
	return card

func _on_main_button_pressed() -> void:
	print("[LevelBattle] 主按钮：", $MainButton.text)

func _on_back_pressed() -> void:
	back_to_menu()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		back_to_menu()

func back_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/menu_main.tscn")
