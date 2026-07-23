extends Node
class_name AllyAIController

## 友军AI控制器 - 控制友方NPC飞船跟随玩家
## 自动跟随玩家飞船，攻击玩家锁定的敌人

enum AllyState { FOLLOW, ENGAGE, RETURN }

@export var follow_distance: float = 1500.0  # 跟随距离
@export var engage_range: float = 8000.0     # 攻击范围

var owner_ship: Ship
var player_ship: Ship = null
var current_state: AllyState = AllyState.FOLLOW
var current_target: Ship = null
var orbit_angle: float = 0.0
var random_offset: Vector3

func _ready() -> void:
	owner_ship = get_parent() as Ship
	# 随机偏移使友军分散跟随
	random_offset = Vector3(
		randf_range(-300.0, 300.0),
		0.0,
		randf_range(-300.0, 300.0)
	)
	await get_tree().process_frame
	_find_player()

func _find_player() -> void:
	var ships = get_tree().get_nodes_in_group("player_ship")
	if ships.size() > 0:
		player_ship = ships[0] as Ship
	if not player_ship:
		player_ship = get_node_or_null("/root/SpaceWar/PlayerShip") as Ship

func _process(delta: float) -> void:
	if not owner_ship or not owner_ship.is_alive:
		return
	if not player_ship or not is_instance_valid(player_ship):
		_find_player()
		return
	
	match current_state:
		AllyState.FOLLOW:
			_process_follow(delta)
		AllyState.ENGAGE:
			_process_engage(delta)
		AllyState.RETURN:
			_process_return(delta)

func _physics_process(delta: float) -> void:
	if not owner_ship or not owner_ship.is_alive:
		return
	owner_ship._handle_movement(delta)

## 跟随状态 - 保持在玩家附近
func _process_follow(_delta: float) -> void:
	if not player_ship or not is_instance_valid(player_ship):
		return
	
	var target_pos = player_ship.global_position + random_offset
	var dist = owner_ship.global_position.distance_to(target_pos)
	
	if dist > follow_distance * 1.5:
		owner_ship.order_move_to(target_pos)
	else:
		owner_ship.has_move_order = false
		owner_ship.has_velocity_order = false
	
	# 检查是否有可攻击的敌人
	_detect_hostiles()

## 交战状态
func _process_engage(delta: float) -> void:
	if not current_target or not current_target.is_alive:
		current_target = null
		current_state = AllyState.RETURN
		return
	
	# 锁定并攻击
	if current_target not in owner_ship.locked_targets:
		owner_ship.lock_target(current_target)
	owner_ship.set_active_target(current_target)
	
	# 环绕攻击
	_orbit_target(delta)
	
	# 射击
	owner_ship.fire_weapons(current_target, delta)
	
	# 如果目标距离玩家太远，放弃攻击返回
	if player_ship and is_instance_valid(player_ship):
		var dist_to_player = current_target.global_position.distance_to(player_ship.global_position)
		if dist_to_player > engage_range * 2:
			owner_ship.unlock_target(current_target)
			current_target = null
			current_state = AllyState.RETURN

## 返回状态 - 返回玩家身边
func _process_return(_delta: float) -> void:
	if not player_ship or not is_instance_valid(player_ship):
		return
	
	var target_pos = player_ship.global_position + random_offset
	var dist = owner_ship.global_position.distance_to(target_pos)
	
	if dist < follow_distance:
		current_state = AllyState.FOLLOW
	else:
		owner_ship.order_move_to(target_pos)
		_detect_hostiles()

## 探测敌对目标
func _detect_hostiles() -> void:
	if not player_ship or not is_instance_valid(player_ship):
		return
	
	var root = get_tree().current_scene
	if not root:
		return
	
	var nearest: Ship = null
	var nearest_dist: float = engage_range
	
	_find_hostiles_recursive(root, nearest, nearest_dist)
	
	if nearest:
		current_target = nearest
		current_state = AllyState.ENGAGE
		owner_ship.lock_target(current_target)

func _find_hostiles_recursive(node: Node, result: Ship, max_dist: float) -> Ship:
	var found = result
	for child in node.get_children():
		if child is Ship and child.faction == Ship.Faction.NPC_HOSTILE and child.is_alive:
			var dist = owner_ship.global_position.distance_to(child.global_position)
			if dist < max_dist:
				found = child
				max_dist = dist
		found = _find_hostiles_recursive(child, found, max_dist)
	return found

## 环绕目标
func _orbit_target(delta: float) -> void:
	if not current_target:
		return
	
	var ship_pos = owner_ship.global_position
	var target_pos = current_target.global_position
	var to_target = target_pos - ship_pos
	var distance = to_target.length()
	
	if distance < 1.0:
		return
	
	orbit_angle += delta * 0.5
	
	var radial_dir = to_target / distance
	var tangential_dir = radial_dir.cross(Vector3.UP)
	if tangential_dir.length() < 0.01:
		tangential_dir = Vector3.RIGHT
	tangential_dir = tangential_dir.normalized()
	
	# 根据船型调整环绕半径
	var orbit_range = 1200.0
	if owner_ship.ship_data:
		match owner_ship.ship_data.ship_class:
			ShipData.ShipClass.CRUISER:
				orbit_range = 2500.0
			ShipData.ShipClass.BATTLESHIP:
				orbit_range = 5000.0
	
	var distance_error = distance - orbit_range
	var radial_speed = 0.0
	if abs(distance_error) > orbit_range * 0.2:
		radial_speed = sign(distance_error) * owner_ship.max_speed * 0.3
	
	var tangential_speed = owner_ship.max_speed * 0.6
	var final_velocity = radial_dir * radial_speed + tangential_dir * tangential_speed
	
	owner_ship.order_set_velocity(final_velocity)

## 设置跟随的玩家飞船
func set_player_ship(ship: Ship) -> void:
	player_ship = ship
