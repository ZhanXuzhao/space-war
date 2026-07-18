extends Node

## 交互控制器 - 处理鼠标点击、右键菜单等交互
## EVE风格操作

enum ClickMode { SELECT, MOVE, ATTACK, MINE }

## Alt+点击目标时发射，通知 HUD 显示目标信息面板
signal target_info_requested(node: Node3D)

var current_mode: ClickMode = ClickMode.SELECT
var player_ship: PlayerShip = null

var _right_click_press_pos: Vector2 = Vector2.ZERO
var _right_click_pressed: bool = false

func _ready() -> void:
	await get_tree().process_frame
	_find_player()

func _find_player() -> void:
	var ships = get_tree().get_nodes_in_group("player_ship")
	if ships.size() > 0:
		player_ship = ships[0] as PlayerShip
	if not player_ship:
		player_ship = get_node_or_null("/root/SpaceWar/PlayerShip") as PlayerShip

func _input(event: InputEvent) -> void:
	if not player_ship:
		return
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_handle_left_click(event)

func _get_camera() -> Camera3D:
	return get_viewport().get_camera_3d()

func _handle_right_click(_event: InputEventMouseButton) -> void:
	var cam = _get_camera()
	if not cam:
		return
	var space_state = get_viewport().get_world_3d().direct_space_state
	var mouse_pos = get_viewport().get_mouse_position()
	var origin = cam.project_ray_origin(mouse_pos)
	var direction = cam.project_ray_normal(mouse_pos)
	var ray_end = origin + direction * 50000.0
	
	var query = PhysicsRayQueryParameters3D.create(origin, ray_end)
	query.collide_with_areas = true
	var result = space_state.intersect_ray(query)
	
	if result:
		var collider = result.collider
		# 点击飞船 - 锁定/攻击
		if collider is Ship and collider != player_ship:
			if collider.faction == Ship.Faction.NPC_HOSTILE:
				player_ship.try_lock_ship(collider)
			else:
				player_ship.order_move_to(result.position)
		# 点击小行星 - 采矿/接近
		elif collider is Asteroid:
			var asteroid = collider as Asteroid
			# 移动到小行星附近
			player_ship.order_move_to(asteroid.global_position)
		# 点击空间站 - 停靠
		elif collider is Station:
			var station = collider as Station
			player_ship.order_move_to(station.global_position)
		# 点击地面 - 移动
		else:
			player_ship.order_move_to(result.position)
	else:
		# 点击虚空 - 移动到该方向
		var move_pos = origin + direction * 5000.0
		player_ship.order_move_to(move_pos)

func _handle_left_click(event: InputEventMouseButton) -> void:
	var cam = _get_camera()
	if not cam:
		return
	var space_state = get_viewport().get_world_3d().direct_space_state
	if not space_state:
		return
	var mouse_pos = get_viewport().get_mouse_position()
	var origin = cam.project_ray_origin(mouse_pos)
	var direction = cam.project_ray_normal(mouse_pos)
	var ray_end = origin + direction * 50000.0
	
	var query = PhysicsRayQueryParameters3D.create(origin, ray_end)
	var result = space_state.intersect_ray(query)
	
	# Alt+左键 → 显示目标信息面板 + 相机锁定
	if event.alt_pressed:
		if result:
			var collider = result.collider
			if collider is Node3D:
				player_ship.set_camera_focus(collider)
				target_info_requested.emit(collider)
			else:
				player_ship.clear_camera_focus()
				target_info_requested.emit(null)
		else:
			player_ship.clear_camera_focus()
			target_info_requested.emit(null)
		return
	
	if result:
		var collider = result.collider
		if collider is Ship and collider != player_ship:
			target_info_requested.emit(collider)
		elif collider is Asteroid:
			target_info_requested.emit(collider)
		elif collider is Station:
			target_info_requested.emit(collider)
