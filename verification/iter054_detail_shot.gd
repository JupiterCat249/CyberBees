extends Node
## 【验证用 · 非生产】详情区实机截图：开局 → 点一张手牌 → 截图（证明详情区接通）
func _ready() -> void:
	var scene: Control = (load("res://scenes/ui/battle_scene.tscn") as PackedScene).instantiate()
	add_child(scene)
	for i in 30:
		await get_tree().process_frame
	# 选中并展示第 3 张手牌（熊蜂，费用 5，四维有区分度）
	var st = scene.state
	var idx := 2 if st.hand[0].size() > 2 else 0
	if st.hand[0].size() > idx:
		var card: CardData = st.hand[0][idx]
		scene._on_hand_clicked(card.id, 0)
		print("[DETAIL_SHOT] 展示：", card.display_name)
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://verification/iter054_detail_shot.png")
	print("[DETAIL_SHOT] saved")
	get_tree().quit(0)
