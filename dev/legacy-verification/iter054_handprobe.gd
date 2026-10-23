extends Node
## 【验证用 · 非生产】手牌绑定探针：打印每张手牌绑定的 卡名/cost，以及徽章节点实际文本
func _ready() -> void:
	var ps: PackedScene = load("res://scenes/ui/battle_scene.tscn")
	var scene: Control = ps.instantiate()
	add_child(scene)
	for i in 40:
		await get_tree().process_frame
	var st = scene.state
	print("===== 手牌探针 =====")
	for side in [0, 1]:
		var names := []
		for c in st.hand[side]:
			names.append("%s(cost=%d)" % [c.display_name, c.cost])
		print("  side=%d 手牌: %s" % [side, str(names)])
	for panel in ["Battle/HandPanelLeft/HandLeft", "Battle/HandPanelRight/HandRight"]:
		var p: Node = scene.get_node(panel)
		print("  --- %s 子节点数=%d ---" % [panel, p.get_child_count()])
		for i in p.get_child_count():
			var card: Node = p.get_child(i)
			var badge := card.get_node_or_null("BadgeImage/Value")
			var img := card.get_node_or_null("Artwork/ArtPlane/Image")
			var cd = card.get("card_data")
			print("     [%d] %s 卡名=%s cost=%s | 徽章节点=%s 文本=%s | 立绘=%s" % [
				i, card.name,
				str(cd.display_name) if cd != null else "null",
				str(cd.cost) if cd != null else "-",
				"有" if badge != null else "无",
				str(badge.text) if badge != null else "-",
				"有" if (img != null and img.texture != null) else "无"])
	get_tree().quit(0)
