extends Node

## 交互控制器 - 处理鼠标点击、右键菜单等交互
## EVE风格操作

enum ClickMode { SELECT, MOVE, ATTACK, MINE }

## Alt+点击目标时发射，通知 HUD 显示目标信息面板
signal target_info_requested(node: Node3D)

var current_mode: ClickMode = ClickMode.SELECT
var player_ship: Ship = null
var _player_controller: Node = null

var _right_click_press_pos: Vector2 = Vector2.ZERO
var _right_click_pressed: bool = false

func _ready() -> void:
	await get_tree().process_frame
	_find_player()
	set_process(true)

func _process(_delta: float) -> void:
	if not player_ship:
		return
	if Input.is_key_pressed(KEY_Q):
		_update_move_preview()
	else:
		if player_ship and player_ship.has_method("hide_move_preview"):
			player_ship.hide_move_preview()

func _find_player() -> void:
	var ships = get_tree().get_nodes_in_group("player_ship")
	if ships.size() > 0:
		player_ship = ships[0] as Ship
		_player_controller = _find_player_controller(player_ship)
	if not player_ship:
		player_ship = get_node_or_null("/root/SpaceWar/PlayerShip") as Ship
		if player_ship:
			_player_controller = _find_player_controller(player_ship)
	# 如果以上方式都找不到 PlayerController，尝试在当前父节点中查找
	if not _player_controller:
		_player_controller = _find_player_controller(get_parent())

## 在飞船节点中查找 PlayerController（支持名称查找和类型查找）
func _find_player_controller(ship: Node) -> Node:
	if not ship:
		return null
	# 优先通过名称查找
	var ctrl = ship.get_node_or_null("PlayerController")
	if ctrl and ctrl.has_method("set_camera_focus"):
		return ctrl
	# 遍历所有直接子节点查找 PlayerController 类型的节点
	for child in ship.get_children():
		if child is PlayerController:
			return child
		# 也检查子节点名称
		if child.has_method("set_camera_focus"):
			return child
	return null

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
				if _player_controller and _player_controller.has_method("try_lock_ship"):
					_player_controller.try_lock_ship(collider)
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
	
	# Q+左键 → 移动命令（类似右键行为）
	if Input.is_key_pressed(KEY_Q):
		_handle_q_left_click(result, origin, direction)
		return
	
	# Alt+左键 → 显示目标信息面板 + 相机锁定（点击虚空不执行操作）
	if event.alt_pressed:
		if result:
			var collider = result.collider
			if collider is Node3D:
				if _player_controller and _player_controller.has_method("set_camera_focus"):
					_player_controller.set_camera_focus(collider)
				target_info_requested.emit(collider)
			else:
				if _player_controller and _player_controller.has_method("clear_camera_focus"):
					_player_controller.clear_camera_focus()
				target_info_requested.emit(null)
		# 点击虚空 → 不执行任何操作
		return
	
	if result:
		var collider = result.collider
		if collider is Ship and collider != player_ship:
			target_info_requested.emit(collider)
		elif collider is Asteroid:
			target_info_requested.emit(collider)
		elif collider is Station:
			target_info_requested.emit(collider)

## 计算鼠标射线与飞船本地 XZ 平面（战术网格面）的交点
## 返回世界空间中的目标位置；若射线平行于平面或交点在后方则返回 null
func _get_grid_intersection() -> Variant:
	if not player_ship:
		return null
	var cam = _get_camera()
	if not cam:
		return null
	var mouse_pos = get_viewport().get_mouse_position()
	var origin = cam.project_ray_origin(mouse_pos)
	var direction = cam.project_ray_normal(mouse_pos)

	# 战术网格在飞船的本地 XZ 平面（y=0），世界空间中的平面法线 = ship.basis.y
	var ship = player_ship
	var plane_normal = ship.global_basis.y
	var plane_point = ship.global_position
	var denom = plane_normal.dot(direction)
	if abs(denom) < 0.0001:
		return null  # 射线平行于平面，无交点

	var t = plane_normal.dot(plane_point - origin) / denom
	if t < 0:
		return null  # 交点在相机后方

	return origin + direction * t

## 更新移动预览（Q 按下时每帧调用）
func _update_move_preview() -> void:
	if not player_ship:
		return
	var world_target = _get_grid_intersection()
	if world_target != null:
		if player_ship.has_method("show_move_preview"):
			player_ship.show_move_preview(world_target)
	else:
		if player_ship.has_method("hide_move_preview"):
			player_ship.hide_move_preview()

## Q+左键 → 移动到鼠标射线与飞船 XZ 平面（战术网格面）的交点
func _handle_q_left_click(_result: Dictionary, _origin: Vector3, _direction: Vector3) -> void:
	if not player_ship:
		return
	var world_target = _get_grid_intersection()
	if world_target != null:
		player_ship.order_move_to(world_target)
