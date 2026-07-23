extends Node3D
class_name Main

const AllyAI = preload("res://scripts/fleet/AllyAIController.gd")

## 主场景脚本 - 负责根据玩家船型动态生成对应飞船
## 现在生成 3 艘玩家飞船（每类船型各一艘），第一艘为主控

func _ready() -> void:
	# 等待一帧确保所有子节点就绪
	await get_tree().process_frame
	
	var fleet_manager = get_node_or_null("/root/FleetManager")
	
	# 生成主控飞船（战列舰）
	var primary_ship = _spawn_primary_ship()
	
	# 生成友军飞船（巡洋舰、护卫舰）
	var ally_classes = [ShipData.ShipClass.CRUISER, ShipData.ShipClass.FRIGATE]
	var ally_ships: Array = []
	for cls in ally_classes:
		var ally = _spawn_ally_ship(cls, primary_ship)
		if ally:
			ally_ships.append(ally)
	
	# 创建默认舰队并加入所有飞船
	if fleet_manager:
		var fleet = fleet_manager.create_fleet("第一舰队")
		if fleet:
			fleet_manager.add_ship_to_fleet(primary_ship, fleet.fleet_id)
			for ally in ally_ships:
				fleet_manager.add_ship_to_fleet(ally, fleet.fleet_id)
	
	print("Main: 玩家舰队已生成 - 共 %d 艘飞船" % (1 + ally_ships.size()))

## 生成主控飞船（带 PlayerController 和相机）
func _spawn_primary_ship() -> Ship:
	# 使用战列舰作为主控
	Global.player_ship_class = ShipData.ShipClass.BATTLESHIP
	Global.player_ship_data_resource = ShipData.get_preset(ShipData.ShipClass.BATTLESHIP)
	
	var ship = Global.spawn_player_ship()
	if ship:
		ship.name = "PlayerShip"
		ship.faction_name = FleetManager.PLAYER_FACTION_NAME
		add_child(ship)
		
		# 注册到舰队管理器
		var fm = get_node_or_null("/root/FleetManager")
		if fm:
			fm.register_player_ship(ship)
		
		# 通知 HUD 更新引用
		var hud = get_node_or_null("HUD")
		if hud and hud.has_method("on_player_ship_changed"):
			hud.on_player_ship_changed(ship)
		
		print("Main: 主控飞船已生成 - ", Global.player_ship_data_resource.ship_name)
	return ship

## 生成友军飞船（带 AllyAIController）
func _spawn_ally_ship(ship_class: ShipData.ShipClass, leader: Ship) -> Ship:
	var scene = Global.get_player_ship_scene(ship_class)
	var ship = scene.instantiate()
	
	ship.ship_data = ShipData.get_preset(ship_class)
	ship.ship_data.ship_name = Ship.generate_random_name(ship_class)
	ship.faction = Ship.Faction.PLAYER
	ship.faction_name = FleetManager.PLAYER_FACTION_NAME
	
	# 添加友军AI控制器
	var ai = AllyAI.new()
	ai.follow_distance = 1200.0
	ai.engage_range = 10000.0
	ship.add_child(ai)
	
	# 添加交互控制器
	if not ship.get_node_or_null("InteractionController"):
		var ic = Node.new()
		ic.name = "InteractionController"
		ic.set_script(preload("res://scripts/ui/InteractionController.gd"))
		ship.add_child(ic)
	
	# 添加模块管理器
	if not ship.get_node_or_null("ModuleManager"):
		var mm = Node.new()
		mm.name = "ModuleManager"
		mm.set_script(preload("res://scripts/modules/ModuleManager.gd"))
		ship.add_child(mm)
	
	# 随机偏移生成位置
	var offset = Vector3(randf_range(-500.0, 500.0), 0, randf_range(-500.0, 500.0))
	var spawn_pos = leader.global_position + offset
	
	ship.name = "AllyShip_%s" % ShipData.SHIP_CLASS_NAMES.get(ship_class, "Unknown")
	add_child(ship)
	ship.global_position = spawn_pos
	
	# 注册到舰队管理器
	var fm = get_node_or_null("/root/FleetManager")
	if fm:
		fm.register_player_ship(ship)
	
	print("Main: 友军飞船已生成 - ", ship.ship_data.ship_name)
	return ship
