extends Node
class_name PlayerController

## 玩家控制器 - 操控 Ship 的输入/相机/跃迁等玩家特有逻辑
## 作为 Ship 的子节点挂载，与 AIController 平级

enum FlightMode { NORMAL, WARPING, JUMPING }

signal warp_started(target_location: Vector3)
signal warp_finished()
signal module_activated(slot_index: int, module_name: String)

## 被控制的飞船
var controlled_ship: Ship

## 飞行模式
var flight_mode: FlightMode = FlightMode.NORMAL
var warp_target: Vector3 = Vector3.ZERO
var warp_progress: float = 0.0
@export var warp_charge_time: float = 3.0
var warp_charging: bool = false
@export var warp_acceleration: float = 500.0

## 环绕目标
var orbit_target: Node3D = null
var orbit_range: float = 1200.0
var orbit_angle: float = 0.0

## 视角控制
@export var camera_orbit_speed: float = 0.005
@export var camera_zoom_speed: float = 5.0
@export var camera_min_distance: float = 50.0
@export var camera_max_distance: float = 50000.0
@export var camera_default_distance: float = 900.0

var _camera: Camera3D
var _cam_distance: float = 900.0
var _cam_azimuth: float = 0.0
var _cam_elevation: float = 15.0
var _left_click_pressed: bool = false
var _left_click_drag_start: Vector2 = Vector2.ZERO
var is_left_click_drag: bool = false
var _camera_look_at_pos: Vector3 = Vector3.ZERO

## 环绕轨迹追踪
var _trajectory_shown_target: Ship = null
const ORBIT_TRAJECTORY_RADIUS: float = 1200.0

## 相机锁定目标
var camera_focus_target: Node3D = null

func _ready() -> void:
	controlled_ship = get_parent() as Ship
	if not controlled_ship:
		push_error("PlayerController: 父节点必须是 Ship!")
		return
	
	controlled_ship.add_to_group("player_ship")
	_setup_camera()
	_adjust_for_ship_class()
	_cam_distance = camera_default_distance
	_camera_look_at_pos = controlled_ship.global_position

func _setup_camera() -> void:
	_camera = get_node_or_null("../Camera3D") as Camera3D
	if not _camera:
		_camera = Camera3D.new()
		_camera.name = "Camera3D"
		_camera.near = 0.5
		_camera.far = 100000.0
		_camera.current = true
		var cam_basis = Basis(Vector3(1, 0, 0), Vector3(0, 0.949, -0.316), Vector3(0, 0.316, 0.949))
		_camera.transform = Transform3D(cam_basis, Vector3(0, 10, 30))
		controlled_ship.call_deferred("add_child", _camera)

func _adjust_for_ship_class() -> void:
	if not controlled_ship or not controlled_ship.ship_data:
		return
	match controlled_ship.ship_data.ship_class:
		ShipData.ShipClass.FRIGATE:
			orbit_range = 1200.0
			camera_default_distance = 900.0
		ShipData.ShipClass.CRUISER:
			orbit_range = 2500.0
			camera_default_distance = 2000.0
		ShipData.ShipClass.BATTLESHIP:
			orbit_range = 5000.0
			camera_default_distance = 4000.0
	_cam_distance = camera_default_distance

func _process(delta: float) -> void:
	if not controlled_ship or not controlled_ship.is_alive:
		return
	
	match flight_mode:
		FlightMode.NORMAL:
			_process_normal_flight(delta)
		FlightMode.WARPING:
			_process_warp(delta)
	
	_update_camera()

func _physics_process(delta: float) -> void:
	if not controlled_ship or not controlled_ship.is_alive:
		return
	if flight_mode == FlightMode.NORMAL:
		controlled_ship._handle_movement(delta)

## 正常飞行模式
func _process_normal_flight(delta: float) -> void:
	_update_orbit(delta)
	
	if controlled_ship.has_move_order and not controlled_ship.approach_target:
		var dist = controlled_ship.global_position.distance_to(controlled_ship.move_target)
		if dist < 50.0:
			controlled_ship.has_move_order = false

# ---------------------------------------------------------------------------
# 环绕系统
# ---------------------------------------------------------------------------

## 环绕目标飞行（径向+切向速度分配优化）
func _update_orbit(delta: float) -> void:
	if not orbit_target or not is_instance_valid(orbit_target):
		if orbit_target:
			cancel_orbit()
		return
	if flight_mode != FlightMode.NORMAL:
		return
	
	var ship_pos = controlled_ship.global_position
	var target_pos = orbit_target.global_position
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
	var vertical_dir = radial_dir.cross(tangential_dir).normalized()
	
	var distance_error = distance - orbit_range
	var abs_error = abs(distance_error)
	var dead_zone = orbit_range * 0.2
	
	var radial_speed = 0.0
	if abs_error > dead_zone:
		var factor = minf(abs_error / (orbit_range * 0.5), 1.0)
		radial_speed = sign(distance_error) * controlled_ship.max_speed * factor
	else:
		radial_speed = distance_error * 0.3
	
	var radial_factor = minf(abs_error / maxf(dead_zone, 1.0), 1.0)
	var tangential_speed = controlled_ship.max_speed * 0.6 * (1.0 - radial_factor * 0.8)
	var vertical_speed = sin(orbit_angle * 0.7) * controlled_ship.max_speed * 0.2
	
	var final_velocity = (
		radial_dir * radial_speed +
		tangential_dir * tangential_speed +
		vertical_dir * vertical_speed
	)
	
	controlled_ship.order_set_velocity(final_velocity)

## 命令飞船环绕目标飞行
func order_orbit(target: Node3D, range: float = 1200.0) -> void:
	if not target or not is_instance_valid(target):
		return
	controlled_ship.cancel_approach()
	
	if target is Ship and target.is_alive:
		_update_trajectory_visual(_trajectory_shown_target, target)
	
	orbit_target = target
	orbit_range = range
	orbit_angle = 0.0
	
	add_message("开始环绕: " + target.name, Color(0.3, 0.8, 1))

## 取消环绕
func cancel_orbit() -> void:
	if orbit_target and is_instance_valid(orbit_target):
		if orbit_target is Ship:
			orbit_target.hide_orbit_trajectory()
			_trajectory_shown_target = null
	orbit_target = null
	controlled_ship.has_velocity_order = false

## 刷新环绕轨迹
func _update_trajectory_visual(old_target: Ship, new_target: Ship) -> void:
	if old_target and is_instance_valid(old_target):
		old_target.hide_orbit_trajectory()
	if new_target and new_target.is_alive:
		new_target.show_orbit_trajectory(ORBIT_TRAJECTORY_RADIUS)
	_trajectory_shown_target = new_target

# ---------------------------------------------------------------------------
# 跃迁系统
# ---------------------------------------------------------------------------

## 跃迁到位置
func warp_to(target_pos: Vector3) -> void:
	if flight_mode != FlightMode.NORMAL:
		return
	if not controlled_ship.use_capacitor(controlled_ship.max_capacitor * 0.3):
		return
	
	warp_target = target_pos
	warp_charging = true
	warp_progress = 0.0
	warp_started.emit(target_pos)
	flight_mode = FlightMode.WARPING

func _process_warp(delta: float) -> void:
	if not warp_charging:
		return
	
	warp_progress += delta / warp_charge_time
	controlled_ship.current_speed = move_toward(controlled_ship.current_speed, controlled_ship.max_speed * 20.0, warp_acceleration * delta)
	controlled_ship.velocity = -controlled_ship.global_basis.z * controlled_ship.current_speed
	controlled_ship.move_and_slide()
	
	var dist = controlled_ship.global_position.distance_to(warp_target)
	if dist < 500.0 or warp_progress >= 1.0:
		_finish_warp()

func _finish_warp() -> void:
	controlled_ship.global_position = warp_target
	controlled_ship.current_speed = 0.0
	flight_mode = FlightMode.NORMAL
	warp_charging = false
	warp_finished.emit()

# ---------------------------------------------------------------------------
# 目标与攻击
# ---------------------------------------------------------------------------

## 鼠标左键 - 选择/锁定目标
func try_lock_ship(target: Ship) -> void:
	if target == controlled_ship:
		return
	if not target.is_alive:
		return
	
	if target in controlled_ship.locked_targets:
		controlled_ship.set_active_target(target)
		controlled_ship.target_locked.emit(target)
	else:
		controlled_ship.lock_target(target)
		controlled_ship.set_active_target(target)

## 鼠标右键 - 移动到目标位置（会取消环绕）
func order_move_to(position: Vector3) -> void:
	if flight_mode != FlightMode.NORMAL:
		return
	if orbit_target:
		cancel_orbit()
	controlled_ship.cancel_approach()
	controlled_ship.order_move_to(position)

## 设置自动攻击
func set_auto_fire(enabled: bool) -> void:
	if enabled:
		if controlled_ship.active_target:
			for w in controlled_ship.weapon_nodes:
				if w is Weapon:
					w.assign_target(controlled_ship.active_target)
		add_message("自动攻击: 开启", Color(1, 0.3, 0.3))
	else:
		for w in controlled_ship.weapon_nodes:
			if w is Weapon:
				w.clear_target()
		add_message("自动攻击: 关闭", Color(0.7, 0.7, 0.7))

# ---------------------------------------------------------------------------
# 相机系统
# ---------------------------------------------------------------------------

## 获取摄像机
func get_camera() -> Camera3D:
	return _camera

func get_cam_distance() -> float:
	return _cam_distance

## 设置相机锁定到目标
func set_camera_focus(target: Node3D) -> void:
	_camera_look_at_pos = _get_camera_look_at_pos()
	camera_focus_target = target
	if target:
		add_message("相机锁定: " + target.name, Color(0.3, 0.8, 1))
	else:
		add_message("相机解锁", Color(0.7, 0.7, 0.7))

func clear_camera_focus() -> void:
	set_camera_focus(null)

func _get_camera_look_at_pos() -> Vector3:
	if camera_focus_target and is_instance_valid(camera_focus_target) and camera_focus_target.is_inside_tree():
		return camera_focus_target.global_position
	return controlled_ship.global_position

func _update_camera() -> void:
	if not _camera or not _camera.is_inside_tree() or not controlled_ship:
		return
	var rad_az = deg_to_rad(_cam_azimuth)
	var rad_el = deg_to_rad(_cam_elevation)
	var offset = Vector3(
		_cam_distance * cos(rad_el) * sin(rad_az),
		_cam_distance * sin(rad_el),
		_cam_distance * cos(rad_el) * cos(rad_az)
	)
	
	var desired_pos: Vector3
	if camera_focus_target and is_instance_valid(camera_focus_target) and camera_focus_target.is_inside_tree():
		desired_pos = camera_focus_target.global_position
	else:
		camera_focus_target = null
		desired_pos = controlled_ship.global_position
	
	var weight = 1.0 - exp(-3.0 * get_process_delta_time())
	_camera_look_at_pos = _camera_look_at_pos.lerp(desired_pos, weight)
	
	_camera.global_position = _camera_look_at_pos + offset
	_camera.look_at(desired_pos, Vector3.UP)

# ---------------------------------------------------------------------------
# 输入处理
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not controlled_ship or not controlled_ship.is_alive:
		return
	
	# F1 切换武器激活
	if event.is_action_pressed("weapon_group_1"):
		for weapon in controlled_ship.weapon_nodes:
			if weapon is Weapon:
				weapon.is_active = not weapon.is_active
	
	# 空格键 - 停止飞船
	if event.is_action_pressed("ui_cancel"):
		controlled_ship.has_move_order = false
		controlled_ship.current_speed = 0.0
	
	# H键 - 重置相机
	if event is InputEventKey and event.pressed and event.keycode == KEY_H:
		clear_camera_focus()
		_cam_azimuth = 0.0
		_cam_elevation = 15.0
		_cam_distance = camera_default_distance
		add_message("相机复位", Color(0.3, 0.8, 1))
	
	# 左键拖拽 - 旋转视角
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_left_click_pressed = true
			_left_click_drag_start = get_viewport().get_mouse_position()
			is_left_click_drag = false
		else:
			_left_click_pressed = false
	
	if event is InputEventMouseMotion and _left_click_pressed:
		if not is_left_click_drag:
			var drag_dist = _left_click_drag_start.distance_to(get_viewport().get_mouse_position())
			if drag_dist > 5.0:
				is_left_click_drag = true
		if is_left_click_drag:
			_cam_azimuth -= event.relative.x * camera_orbit_speed * rad_to_deg(1.0)
			_cam_elevation += event.relative.y * camera_orbit_speed * rad_to_deg(1.0)
			_cam_elevation = clampf(_cam_elevation, -89.0, 89.0)
	
	# 滚轮缩放
	var zoom_step = camera_max_distance * 0.02
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_cam_distance = minf(camera_max_distance, _cam_distance + zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_cam_distance = maxf(camera_min_distance, _cam_distance - zoom_step)
	
	# -= 键 - 调整游戏速度
	const TIMESCALE_STEPS: Array[float] = [0.0, 0.1, 0.5, 1.0, 2.0, 3.0, 5.0]
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_EQUAL or event.keycode == KEY_KP_ADD:
			var cur = Engine.time_scale
			var idx = TIMESCALE_STEPS.find(cur)
			if idx < 0:
				for i in range(TIMESCALE_STEPS.size()):
					if TIMESCALE_STEPS[i] > cur:
						idx = i - 1
						break
			idx = clampi(idx + 1, 0, TIMESCALE_STEPS.size() - 1)
			Engine.time_scale = TIMESCALE_STEPS[idx]
			add_message("游戏速度: x%.1f" % Engine.time_scale, Color(0.3, 0.8, 1))
		elif event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT:
			var cur = Engine.time_scale
			var idx = TIMESCALE_STEPS.find(cur)
			if idx < 0:
				for i in range(TIMESCALE_STEPS.size() - 1, -1, -1):
					if TIMESCALE_STEPS[i] < cur:
						idx = i + 1
						break
			idx = clampi(idx - 1, 0, TIMESCALE_STEPS.size() - 1)
			Engine.time_scale = TIMESCALE_STEPS[idx]
			add_message("游戏速度: x%.1f" % Engine.time_scale, Color(0.3, 0.8, 1))

# ---------------------------------------------------------------------------
# HUD 通信
# ---------------------------------------------------------------------------

func add_message(text: String, color: Color = Color.WHITE) -> void:
	var hud = get_node_or_null("/root/SpaceWar/HUD")
	if hud and hud.has_method("add_message"):
		hud.add_message(text, color)
