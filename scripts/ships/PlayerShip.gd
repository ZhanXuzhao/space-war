extends Ship
class_name PlayerShip

## 玩家飞船控制器
## EVE风格操作：鼠标右键移动、左键选择目标、快捷键激活模块

enum FlightMode { NORMAL, WARPING, JUMPING }

signal warp_started(target_location: Vector3)
signal warp_finished()
signal module_activated(slot_index: int, module_name: String)

@export var rotation_speed: float = 2.0
@export var acceleration: float = 100.0
@export var deceleration: float = 50.0
@export var warp_acceleration: float = 500.0

var flight_mode: FlightMode = FlightMode.NORMAL
var warp_target: Vector3 = Vector3.ZERO
var warp_progress: float = 0.0
var warp_charge_time: float = 3.0
var warp_charging: bool = false
var angular_velocity: Vector3 = Vector3.ZERO

## 模块管理
var module_manager: Node

## 视角控制
@export var camera_orbit_speed: float = 0.005
@export var camera_zoom_speed: float = 5.0
@export var camera_min_distance: float = 10.0
@export var camera_max_distance: float = 500.0
@export var camera_default_distance: float = 30.0

var _camera: Camera3D
var _cam_distance: float = 30.0
var _cam_azimuth: float = 0.0      # 水平角度（度）
var _cam_elevation: float = 15.0   # 俯仰角度（度）
var _right_click_pressed: bool = false
var _right_click_drag_start: Vector2 = Vector2.ZERO
var is_right_click_drag: bool = false

func _ready() -> void:
	super._ready()
	move_target = global_position
	module_manager = get_node_or_null("../ModuleManager")
	_camera = $Camera3D
	_cam_distance = camera_default_distance

func _process(delta: float) -> void:
	super._process(delta)
	
	match flight_mode:
		FlightMode.NORMAL:
			_process_normal_flight(delta)
		FlightMode.WARPING:
			_process_warp(delta)
	
	_update_camera()

func _physics_process(delta: float) -> void:
	if not is_alive:
		return
	
	if flight_mode == FlightMode.NORMAL:
		_handle_movement(delta)

## 正常飞行模式
func _process_normal_flight(delta: float) -> void:
	# 到达目标点后减速
	if has_move_order:
		var dist = global_position.distance_to(move_target)
		if dist < 50.0:
			has_move_order = false

## 移动处理
func _handle_movement(delta: float) -> void:
	if has_move_order and is_alive:
		var direction = (move_target - global_position).normalized()
		var distance = global_position.distance_to(move_target)
		
		# 飞船朝向目标方向旋转 (平滑旋转)
		var target_basis = Basis.looking_at(direction, Vector3.UP)
		global_basis = global_basis.slerp(target_basis, rotation_speed * delta)
		
		# 接近目标时减速
		var speed_factor = 1.0
		if distance < 200.0:
			speed_factor = distance / 200.0
		
		current_speed = move_toward(current_speed, max_speed * speed_factor, acceleration * delta)
		velocity = -global_basis.z * current_speed
	else:
		# 减速
		current_speed = move_toward(current_speed, 0.0, deceleration * delta)
		velocity = -global_basis.z * current_speed
	
	move_and_slide()

## 鼠标右键 - 移动到目标位置
func order_move_to(position: Vector3) -> void:
	if flight_mode != FlightMode.NORMAL:
		return
	super.order_move_to(position)

## 鼠标左键 - 选择/锁定目标
func try_lock_ship(target: Ship) -> void:
	if target == self:
		return
	if not target.is_alive:
		return
	
	if target in locked_targets:
		set_active_target(target)
	else:
		lock_target(target)

## 跃迁到位置 (Warp)
func warp_to(target_pos: Vector3) -> void:
	if flight_mode != FlightMode.NORMAL:
		return
	if not use_capacitor(max_capacitor * 0.3):  # 跃迁消耗30%电容
		return
	
	warp_target = target_pos
	warp_charging = true
	warp_progress = 0.0
	warp_started.emit(target_pos)
	
	# 启动跃迁
	flight_mode = FlightMode.WARPING

func _process_warp(delta: float) -> void:
	if not warp_charging:
		return
	
	warp_progress += delta / warp_charge_time
	
	# 加速
	current_speed = move_toward(current_speed, max_speed * 20.0, warp_acceleration * delta)
	velocity = -global_basis.z * current_speed
	move_and_slide()
	
	var dist = global_position.distance_to(warp_target)
	if dist < 500.0 or warp_progress >= 1.0:
		_finish_warp()

func _finish_warp() -> void:
	global_position = warp_target
	current_speed = 0.0
	flight_mode = FlightMode.NORMAL
	warp_charging = false
	warp_finished.emit()

## 激活模块
func activate_module(slot_index: int, slot_type: String) -> void:
	if not module_manager:
		return
	module_manager.call("activate_module", slot_index, slot_type)

## 射击所有已激活武器
func fire_weapons(target: Ship, delta: float) -> void:
	for weapon in weapon_nodes:
		if weapon is Weapon:
			weapon.try_fire(target, delta)

## 更新相机位置（球面坐标环绕飞船）
func _update_camera() -> void:
	if not _camera:
		return
	var rad_az = deg_to_rad(_cam_azimuth)
	var rad_el = deg_to_rad(_cam_elevation)
	var x = _cam_distance * cos(rad_el) * sin(rad_az)
	var y = _cam_distance * sin(rad_el)
	var z = _cam_distance * cos(rad_el) * cos(rad_az)
	_camera.position = Vector3(x, y, z)
	_camera.look_at(Vector3.ZERO)

## 键盘快捷键
func _input(event: InputEvent) -> void:
	if not is_alive:
		return
	
	# F1-F8 激活武器/模块
	if event.is_action_pressed("weapon_group_1"):
		for weapon in weapon_nodes:
			if weapon is Weapon:
				weapon.is_active = not weapon.is_active
	
	# 空格键 - 停止飞船
	if event.is_action_pressed("ui_cancel"):
		has_move_order = false
		current_speed = 0.0
	
	# 右键拖拽 - 旋转视角
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_right_click_pressed = true
			_right_click_drag_start = get_viewport().get_mouse_position()
			is_right_click_drag = false
		else:
			_right_click_pressed = false
	
	if event is InputEventMouseMotion and _right_click_pressed:
		if not is_right_click_drag:
			var drag_dist = _right_click_drag_start.distance_to(get_viewport().get_mouse_position())
			if drag_dist > 5.0:
				is_right_click_drag = true
		if is_right_click_drag:
			_cam_azimuth -= event.relative.x * camera_orbit_speed * rad_to_deg(1.0)
			_cam_elevation += event.relative.y * camera_orbit_speed * rad_to_deg(1.0)
			_cam_elevation = clampf(_cam_elevation, -89.0, 89.0)
	
	# 滚轮 - 拉近拉远
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_cam_distance = maxf(camera_min_distance, _cam_distance - camera_zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_cam_distance = minf(camera_max_distance, _cam_distance + camera_zoom_speed)
