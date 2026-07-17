extends Node3D
class_name Main

## 主场景脚本 - 负责根据玩家船型动态生成对应飞船

func _ready() -> void:
	# 等待一帧确保所有子节点就绪
	await get_tree().process_frame
	
	# 使用 Global 生成对应船型的玩家飞船
	var ship = Global.spawn_player_ship()
	if ship:
		ship.name = "PlayerShip"
		add_child(ship)
		
		# 通知 HUD 更新引用
		var hud = get_node_or_null("HUD")
		if hud and hud.has_method("on_player_ship_changed"):
			hud.on_player_ship_changed(ship)
		
		print("Main: 玩家飞船已生成 - ", Global.player_ship_data_resource.ship_name)
