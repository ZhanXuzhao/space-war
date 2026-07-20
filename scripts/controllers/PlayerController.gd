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
## 环绕当前速度（每帧以 a·Δt 向目标加速）
var _orbit_current_velocity: Vector3 = Vector3.ZERO

# ---------------------------------------------------------------------------
# 相机系统 — 参数
# ---------------------------------------------------------------------------

## 鼠标拖拽旋转灵敏度
@export var camera_orbit_speed: float = 0.005
## 滚轮缩放灵敏度（系数乘数）
@export var camera_zoom_factor: float = 1.2
## 最近/最远/默认观察距离
@export var camera_min_distance: float = 50.0
@export var camera_max_distance: float = 200000.0
@export var camera_default_distance: float = 900.0

# ---------------------------------------------------------------------------
# 相机系统 — 运行时状态
# ---------------------------------------------------------------------------

## Camera3D 节点引用
var _camera: Camera3D
## 当前球面坐标：距离 / 方位角(°) / 仰角(°)
var _cam_distance: float = 900.0
var _cam_azimuth: float = 0.0
var _cam_elevation: float = 15.0
## 相机轨道中心点（平滑追踪目标）
var _camera_look_at_pos: Vector3 = Vector3.ZERO
## 锁定追踪的目标（不为空时相机围绕此目标旋转）
var camera_focus_target: Node3D = null

# ---------------------------------------------------------------------------
# 相机系统 — 鼠标拖拽输入状态
# ---------------------------------------------------------------------------

var _drag_left_pressed: bool = false
var _drag_left_start_pos: Vector2 = Vector2.ZERO
var _drag_left_is_dragging: bool = false

# ---------------------------------------------------------------------------
# 环绕轨迹追踪
# ---------------------------------------------------------------------------

var _trajectory_shown_target: Ship = null
const ORBIT_TRAJECTORY_RADIUS: float = 1200.0

func _ready() -> void:
	controlled_ship = get_parent() as Ship
	if not controlled_ship:
		push_error("PlayerController: 父节点必须是 Ship!")
		return
	
	controlled_ship.add_to_group("player_ship")
	_setup_camera()
	_adjust_camera_for_ship_class()
	_adjust_orbit_for_ship_class()
	_cam_distance = camera_default_distance
	_camera_look_at_pos = controlled_ship.global_position
	# 镜头最近距离 = 船长 × 2（考虑模型缩放），覆盖 @export 默认值
	camera_min_distance = controlled_ship.SHIP_LENGTH * controlled_ship.scale.x * 2.0

func _setup_camera() -> void:
	_camera = get_node_or_null("../Camera3D") as Camera3D
	if not _camera:
		_camera = Camera3D.new()
		_camera.name = "Camera3D"
		_camera.near = 0.5
		_camera.far = 500000.0
		_camera.current = true
		var cam_basis = Basis(Vector3(1, 0, 0), Vector3(0, 0.949, -0.316), Vector3(0, 0.316, 0.949))
		_camera.transform = Transform3D(cam_basis, Vector3(0, 10, 30))
		controlled_ship.call_deferred("add_child", _camera)

func _adjust_camera_for_ship_class() -> void:
	if not controlled_ship or not controlled_ship.ship_data:
		return
	match controlled_ship.ship_data.ship_class:
		ShipData.ShipClass.FRIGATE:
			camera_default_distance = 900.0
		ShipData.ShipClass.CRUISER:
			camera_default_distance = 2000.0
		ShipData.ShipClass.BATTLESHIP:
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
	
	_update_camera(delta)

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

## 根据船型调整默认环绕半径
func _adjust_orbit_for_ship_class() -> void:
	if not controlled_ship or not controlled_ship.ship_data:
		return
	match controlled_ship.ship_data.ship_class:
		ShipData.ShipClass.FRIGATE:
			orbit_range = 1200.0
		ShipData.ShipClass.CRUISER:
			orbit_range = 2500.0
		ShipData.ShipClass.BATTLESHIP:
			orbit_range = 5000.0

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
	
	# v = v₀ + a·Δt：向目标速度加速，不超过飞船加速度
	var delta_v = final_velocity - _orbit_current_velocity
	var max_delta = controlled_ship.acceleration * delta
	if delta_v.length() > max_delta:
		delta_v = delta_v.normalized() * max_delta
	_orbit_current_velocity += delta_v
	
	controlled_ship.order_set_velocity(_orbit_current_velocity)

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
	_orbit_current_velocity = Vector3.ZERO
	
	add_message("开始环绕: " + target.name, Color(0.3, 0.8, 1))

## 取消环绕
func cancel_orbit() -> void:
	if orbit_target and is_instance_valid(orbit_target):
		if orbit_target is Ship:
			orbit_target.hide_orbit_trajectory()
			_trajectory_shown_target = null
	orbit_target = null
	_orbit_current_velocity = Vector3.ZERO
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
		_align_camera_to_attack_direction(target)
		add_message("相机锁定: " + target.name, Color(0.3, 0.8, 1))
	else:
		add_message("相机解锁", Color(0.7, 0.7, 0.7))

## 当锁定的飞船正在攻击目标时，将相机置于其攻击方向侧后方
func _align_camera_to_attack_direction(target: Node3D) -> void:
	if not (target is Ship and target.is_alive):
		return
	var ship_target = target as Ship
	if not (ship_target.active_target and is_instance_valid(ship_target.active_target) and ship_target.active_target.is_alive):
		return
	# 取攻击目标位置 + 横向偏移作为参考方向
	var offset_pos = ship_target.active_target.global_position \
		+ Vector3(ship_target.current_targeting_range * 0.3, 0, 0)
	var attack_dir = offset_pos - target.global_position
	if attack_dir.length_squared() <= 0.01:
		return
	attack_dir = attack_dir.normalized()
	# 相机置于飞船相对于攻击方向的背后
	var cam_dir = -attack_dir
	_cam_azimuth = rad_to_deg(atan2(cam_dir.x, cam_dir.z))
	_cam_elevation = rad_to_deg(asin(clampf(cam_dir.y, -1.0, 1.0)))

func clear_camera_focus() -> void:
	set_camera_focus(null)

func _get_camera_look_at_pos() -> Vector3:
	if camera_focus_target and is_instance_valid(camera_focus_target) and camera_focus_target.is_inside_tree():
		return camera_focus_target.global_position
	return controlled_ship.global_position

func _update_camera(delta: float) -> void:
	if not _camera or not _camera.is_inside_tree() or not controlled_ship:
		return
	
	# 确定轨道中心目标点
	var desired_pos: Vector3
	if camera_focus_target and is_instance_valid(camera_focus_target) and camera_focus_target.is_inside_tree():
		desired_pos = camera_focus_target.global_position
	else:
		camera_focus_target = null
		desired_pos = controlled_ship.global_position
	
	# 平滑轨道中心（指数逼近）
	var smooth_weight = 1.0 - exp(-3.0 * delta)
	_camera_look_at_pos = _camera_look_at_pos.lerp(desired_pos, smooth_weight)
	
	# 根据球面坐标计算相机偏移
	var offset = _compute_camera_offset()
	_camera.global_position = _camera_look_at_pos + offset
	
	# 旋转用 slerp 平滑追踪实际目标位置，避免抖动
	var target_quat = Quaternion(Basis.looking_at(desired_pos - _camera.global_position, Vector3.UP))
	var rot_weight = 1.0 - exp(-8.0 * delta)
	_camera.quaternion = _camera.quaternion.slerp(target_quat, rot_weight)

## 根据当前球面坐标（方位角/仰角/距离）计算相机相对偏移
func _compute_camera_offset() -> Vector3:
	var rad_az = deg_to_rad(_cam_azimuth)
	var rad_el = deg_to_rad(_cam_elevation)
	return Vector3(
		_cam_distance * cos(rad_el) * sin(rad_az),
		_cam_distance * sin(rad_el),
		_cam_distance * cos(rad_el) * cos(rad_az)
	)

## 当用户主动操作镜头时，立即对齐轨道中心和旋转到实际目标
## 避免 Lerp/Slerp 滞后导致的画面偏移感
func _snap_camera() -> void:
	if camera_focus_target and is_instance_valid(camera_focus_target) and camera_focus_target.is_inside_tree():
		_camera_look_at_pos = camera_focus_target.global_position
	else:
		_camera_look_at_pos = controlled_ship.global_position
	
	_camera.global_position = _camera_look_at_pos + _compute_camera_offset()
	var target_basis = Basis.looking_at(
		(_camera_look_at_pos if camera_focus_target else controlled_ship.global_position) - _camera.global_position,
		Vector3.UP
	)
	_camera.quaternion = Quaternion(target_basis)

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
		_snap_camera()
		add_message("相机复位", Color(0.3, 0.8, 1))
	
	# 左键拖拽 - 旋转视角
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_left_pressed = true
			_drag_left_start_pos = get_viewport().get_mouse_position()
			_drag_left_is_dragging = false
		else:
			_drag_left_pressed = false
	
	if event is InputEventMouseMotion and _drag_left_pressed:
		if not _drag_left_is_dragging:
			var drag_dist = _drag_left_start_pos.distance_to(get_viewport().get_mouse_position())
			if drag_dist > 5.0:
				_drag_left_is_dragging = true
		if _drag_left_is_dragging:
			_cam_azimuth -= event.relative.x * camera_orbit_speed * rad_to_deg(1.0)
			_cam_elevation += event.relative.y * camera_orbit_speed * rad_to_deg(1.0)
			_cam_elevation = clampf(_cam_elevation, -89.0, 89.0)
			_snap_camera()
	
	# 滚轮缩放
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_cam_distance = minf(camera_max_distance, _cam_distance * camera_zoom_factor)
			_snap_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_cam_distance = maxf(camera_min_distance, _cam_distance / camera_zoom_factor)
			_snap_camera()
	
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
