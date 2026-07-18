extends PopupMenu
class_name OverviewContextMenu

## 总览右键菜单 - 右键点击总览条目时弹出
## 提供：锁定、攻击、接近、解锁等操作

signal menu_option_selected(action: String, target_node: Node)

var current_target: Node = null

func _ready() -> void:
	# 连接菜单项选择信号
	id_pressed.connect(_on_item_selected)
	hide()

## 在指定屏幕位置弹出菜单
func show_for_target(target_node: Node, screen_position: Vector2) -> void:
	current_target = target_node
	clear()
	
	# 根据目标类型构建菜单
	if target_node is Ship:
		_build_ship_menu(target_node)
	elif target_node is Asteroid:
		_build_asteroid_menu(target_node)
	elif target_node is Station:
		_build_station_menu(target_node)
	else:
		_build_generic_menu(target_node)
	
	# 设置位置并弹出
	position = screen_position
	popup()

func _build_ship_menu(ship: Ship) -> void:
	add_icon_item(preload("res://icon.svg"), "锁定目标", 1)
	
	# 是否是玩家自身？跳过
	if ship.faction == Ship.Faction.PLAYER:
		return
	
	# 敌对目标显示攻击选项
	if ship.faction == Ship.Faction.NPC_HOSTILE:
		add_icon_item(preload("res://icon.svg"), "攻击目标", 2)
	
	add_icon_item(preload("res://icon.svg"), "接近", 3)
	add_separator()
	add_icon_item(preload("res://icon.svg"), "解锁目标", 4)
	
	# 如果是已锁定目标，显示为目标标记
	var player_ships = ship.get_tree().get_nodes_in_group("player_ship")
	if player_ships.size() > 0:
		var player = player_ships[0] as Ship
		if ship in player.locked_targets:
			add_icon_item(preload("res://icon.svg"), "设为当前目标", 5)

func _build_asteroid_menu(_asteroid: Asteroid) -> void:
	add_icon_item(preload("res://icon.svg"), "接近", 3)
	add_icon_item(preload("res://icon.svg"), "采矿", 6)

func _build_station_menu(_station: Station) -> void:
	add_icon_item(preload("res://icon.svg"), "接近", 3)
	add_icon_item(preload("res://icon.svg"), "停靠", 7)

func _build_generic_menu(_node: Node) -> void:
	add_icon_item(preload("res://icon.svg"), "接近", 3)

func _on_item_selected(id: int) -> void:
	var action = ""
	match id:
		1: action = "lock"
		2: action = "attack"
		3: action = "approach"
		4: action = "unlock"
		5: action = "set_active"
		6: action = "mine"
		7: action = "dock"
		_: action = "approach"
	
	menu_option_selected.emit(action, current_target)
	hide()
