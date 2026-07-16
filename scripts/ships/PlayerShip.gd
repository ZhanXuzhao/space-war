extends Ship
class_name PlayerShip

## 玩家飞船控制器
## EVE风格操作：鼠标右键移动、左键选择目标、快捷键激活模块

enum FlightMode { NORMAL, WARPING, JUMPING }

signal warp_started(target_location: Vector3)
signal warp_finished()
signal module_activated(slot_index: int, module_name: String)

@export var warp_acceleration: float = 500.0

var flight_mode: FlightMode = FlightMode.NORMAL
var warp_target: Vector3 = Vector3.ZERO
var warp_progress: float = 0.0
var warp_charge_time: float = 3.0
var warp_charging: bool = false
var angular_velocity: Vector3 = Vector3.ZERO

## 环绕目标
var orbit_target: Node3D = null
var orbit_range: float = 1200.0
var orbit_angle: float = 0.0

## 模块管理
var module_manager: Node

## 视角控制
@export var camera_orbit_speed: float = 0.005
@export var camera_zoom_speed: float = 5.0
@export var camera_min_distance: float = 50.0
@export var camera_max_distance: float = 50000.0
@export var camera_default_distance: float = 900.0

var _camera: Camera3D
var _cam_distance: float = 900.0  # 默认 camera_default_distance
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
	_camera_look_at_pos = global_position
	# 创建2个激光武器
	_create_laser_weapons()
	# 创建2个导弹武器
	_create_missile_weapons()
	# 创建3个维修装备
	_create_repair_modules()

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
	# 环绕目标飞行
	_update_orbit(delta)
	
	# 到达目标点后减速（持续靠近模式下不取消，继续追踪）
	if has_move_order and not approach_target:
		var dist = global_position.distance_to(move_target)
		if dist < 50.0:
			has_move_order = false

## 移动处理
func _handle_movement(delta: float) -> void:
	if has_velocity_order:
		# 速度指令模式（环绕时径向/切向速度分配）
		var target_speed = velocity_setpoint.length()
		if target_speed > 0.01 and is_alive:
			var target_dir = velocity_setpoint / target_speed
			var target_basis = Basis.looking_at(target_dir, Vector3.UP)
			global_basis = global_basis.slerp(target_basis, rotation_speed * delta)
			current_speed = move_toward(current_speed, target_speed, acceleration * delta)
		else:
			current_speed = move_toward(current_speed, 0.0, deceleration * delta)
		velocity = -global_basis.z * current_speed
	elif has_move_order and is_alive:
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

## 鼠标右键 - 移动到目标位置（会取消环绕）
func order_move_to(position: Vector3) -> void:
	if flight_mode != FlightMode.NORMAL:
		return
	# 手动移动时取消环绕和持续靠近
	if orbit_target:
		cancel_orbit()
	cancel_approach()
	super.order_move_to(position)

## 环绕轨迹追踪
var _trajectory_shown_target: Ship = null
const ORBIT_TRAJECTORY_RADIUS: float = 1200.0

## 环绕目标飞行（径向+切向速度分配优化）
## 将速度分解为径向（修正距离）和切向（维持环绕）分量
func _update_orbit(delta: float) -> void:
	if not orbit_target or not is_instance_valid(orbit_target):
		if orbit_target:
			cancel_orbit()
		return
	if flight_mode != FlightMode.NORMAL:
		return
	
	var ship_pos = global_position
	var target_pos = orbit_target.global_position
	var to_target = target_pos - ship_pos
	var distance = to_target.length()
	
	if distance < 1.0:
		return
	
	orbit_angle += delta * 0.5
	
	# 径向方向（从飞船指向目标）
	var radial_dir = to_target / distance
	
	# 切向方向（与径向垂直，在水平面上）
	var tangential_dir = radial_dir.cross(Vector3.UP)
	if tangential_dir.length() < 0.01:
		tangential_dir = Vector3.RIGHT
	tangential_dir = tangential_dir.normalized()
	
	# 垂直方向（产生立体轨迹）
	var vertical_dir = radial_dir.cross(tangential_dir).normalized()
	
	var distance_error = distance - orbit_range
	var abs_error = abs(distance_error)
	var dead_zone = orbit_range * 0.2
	
	# ===== 径向速度：根据距离误差分配 =====
	var radial_speed = 0.0
	if abs_error > dead_zone:
		# 超出死区：径向优先，全力修正距离
		var factor = minf(abs_error / (orbit_range * 0.5), 1.0)
		radial_speed = sign(distance_error) * max_speed * factor
	else:
		# 在死区内：温和的径向修正
		radial_speed = distance_error * 0.3
	
	# ===== 切向速度：维持环绕 =====
	var radial_factor = minf(abs_error / maxf(dead_zone, 1.0), 1.0)
	var tangential_speed = max_speed * 0.6 * (1.0 - radial_factor * 0.8)
	
	# ===== 垂直速度：立体起伏 =====
	var vertical_speed = sin(orbit_angle * 0.7) * max_speed * 0.2
	
	# ===== 合成最终速度向量 =====
	var final_velocity = (
		radial_dir * radial_speed +
		tangential_dir * tangential_speed +
		vertical_dir * vertical_speed
	)
	
	order_set_velocity(final_velocity)

## 命令飞船环绕目标飞行
func order_orbit(target: Node3D, range: float = 1200.0) -> void:
	if not target or not is_instance_valid(target):
		return
	
	# 环绕时取消持续靠近
	cancel_approach()
	
	# 显示环绕轨迹
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
	has_velocity_order = false

## 鼠标左键 - 选择/锁定目标
func try_lock_ship(target: Ship) -> void:
	if target == self:
		return
	if not target.is_alive:
		return
	
	if target in locked_targets:
		set_active_target(target)
		target_locked.emit(target)
	else:
		lock_target(target)
		set_active_target(target)

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

## 创建2个激光武器（贴于飞船左右表面，高度居中，Z轴均匀分布）
func _create_laser_weapons() -> void:
	for i in range(2):
		var weapon = Weapon.new()
		var wdata = WeaponData.new()
		wdata.weapon_name = "小型激光炮"
		wdata.damage = 25.0
		wdata.damage_type = "热能"
		wdata.rate_of_fire = 1.0 / 3.0
		wdata.optimal_range = 1500.0
		wdata.falloff_range = 3000.0
		wdata.tracking_speed = 1.0
		wdata.capacitor_usage = 5.0
		wdata.projectile_scene = null
		weapon.weapon_data = wdata
		# 贴于飞船左右表面(x=±75)，高度居中(y=0)，左右对称
		var side = 1 if i == 0 else -1  # 左=+1, 右=-1
		var offset = Vector3(75 * side, 0, -75)  # 激光炮在船体前方左右对称
		weapon.position = offset
		weapon.name = "LaserWeapon_%s" % ["Left" if i == 0 else "Right"]
		# 左侧炮台安装平面法线朝左(+X)，右侧朝右(-X)
		weapon.mount_local_normal = Vector3(side, 0, 0)
		add_child(weapon)
		weapon_nodes.append(weapon)
		weapon.activate()

## 创建2个导弹武器
func _create_missile_weapons() -> void:
	var projectile_scene = preload("res://scenes/weapons/Projectile.tscn")
	for i in range(2):
		var weapon = Weapon.new()
		var wdata = WeaponData.new()
		wdata.weapon_name = "轻型导弹发射器"
		wdata.description = "基础导弹武器，发射自导导弹"
		wdata.weapon_type = WeaponData.WeaponType.MISSILE
		wdata.damage = 60.0
		wdata.damage_type = "爆炸"
		wdata.rate_of_fire = 1.0 / 6.0
		wdata.optimal_range = 3000.0
		wdata.falloff_range = 5000.0
		wdata.tracking_speed = 0.5
		wdata.signature_resolution = 40.0
		wdata.capacitor_usage = 15.0
		wdata.projectile_scene = projectile_scene
		weapon.weapon_data = wdata
		# 贴于飞船左右表面(x=±75)，高度居中(y=0)，左右对称
		var side = 1 if i == 0 else -1  # 左=+1, 右=-1
		var offset = Vector3(75 * side, 0, 75)  # 导弹在船体后方左右对称
		weapon.position = offset
		weapon.name = "MissileLauncher_%s" % ["Left" if i == 0 else "Right"]
		# 左侧挂架安装平面法线朝左(+X)，右侧朝右(-X)
		weapon.mount_local_normal = Vector3(side, 0, 0)
		add_child(weapon)
		weapon_nodes.append(weapon)
		weapon.activate()

## 创建3个维修装备：护盾维修、装甲维修、结构维修
func _create_repair_modules() -> void:
	var modules_info = [
		{ "cls": ShieldBooster, "name": "护盾维修器", "amount": 120.0, "cap": 30.0, "time": 3.0 },
		{ "cls": ArmorRepairer, "name": "装甲维修器", "amount": 80.0, "cap": 35.0, "time": 4.0 },
		{ "cls": StructureRepairer, "name": "结构维修器", "amount": 60.0, "cap": 40.0, "time": 5.0 },
	]
	for info in modules_info:
		var mod: ShipModule = info["cls"].new()
		var mdata = ModuleData.new()
		mdata.module_name = info["name"]
		mdata.effect_amount = info["amount"]
		mdata.capacitor_usage = info["cap"]
		mdata.activation_time = info["time"]
		mdata.slot_type = ModuleData.ModuleSlot.LOW
		mod.module_data = mdata
		mod.name = info["name"]
		add_child(mod)
		low_slot_modules.append(mod)

## 射击所有已激活武器
func fire_weapons(target: Ship, delta: float) -> void:
	for weapon in weapon_nodes:
		if weapon is Weapon:
			weapon.try_fire(target, delta)

## 右键点击移动 - 向太空发射射线，移动到点击位置
func _handle_right_click_move() -> void:
	var space_state = get_viewport().get_world_3d().direct_space_state
	var mouse_pos = get_viewport().get_mouse_position()
	var cam = _camera
	if not cam:
		return
	var origin = cam.project_ray_origin(mouse_pos)
	var direction = cam.project_ray_normal(mouse_pos)
	var ray_end = origin + direction * 50000.0
	
	var query = PhysicsRayQueryParameters3D.create(origin, ray_end)
	query.collide_with_areas = true
	var result = space_state.intersect_ray(query)
	
	if result:
		var collider = result.collider
		if collider is Ship and collider != self:
			order_move_to(result.position)
		elif collider is Asteroid:
			order_move_to(collider.global_position)
		elif collider is Station:
			order_move_to(collider.global_position)
		else:
			order_move_to(result.position)
	else:
		var move_pos = origin + direction * 5000.0
		order_move_to(move_pos)

func set_active_target(target: Ship) -> void:
	super.set_active_target(target)

## 刷新环绕轨迹：旧目标隐藏、新目标显示
func _update_trajectory_visual(old_target: Ship, new_target: Ship) -> void:
	if old_target and is_instance_valid(old_target):
		old_target.hide_orbit_trajectory()
	if new_target and new_target.is_alive:
		new_target.show_orbit_trajectory(ORBIT_TRAJECTORY_RADIUS)
	_trajectory_shown_target = new_target

func unlock_target(target: Ship) -> void:
	if target == _trajectory_shown_target and is_instance_valid(target):
		target.hide_orbit_trajectory()
		_trajectory_shown_target = null
	super.unlock_target(target)

func set_auto_fire(enabled: bool) -> void:
	if enabled:
		# 将所有武器分配给当前活跃目标
		if active_target:
			for w in weapon_nodes:
				if w is Weapon:
					w.assign_target(active_target)
		add_message("自动攻击: 开启", Color(1, 0.3, 0.3))
	else:
		# 清除所有武器的目标分配
		for w in weapon_nodes:
			if w is Weapon:
				w.clear_target()
		add_message("自动攻击: 关闭", Color(0.7, 0.7, 0.7))

func add_message(text: String, color: Color = Color.WHITE) -> void:
	var hud = get_node_or_null("../HUD")
	if not hud:
		hud = get_node_or_null("/root/SpaceWar/HUD")
	if hud and hud.has_method("add_message"):
		hud.add_message(text, color)

## 相机锁定目标
var camera_focus_target: Node3D = null
## 相机平滑过渡 - 当前实际观察位置（用于插值）
var _camera_look_at_pos: Vector3 = Vector3.ZERO

func get_cam_distance() -> float:
	return _cam_distance

## 设置相机锁定到目标（Alt+左键点击目标）
func set_camera_focus(target: Node3D) -> void:
	# 记录当前相机观察位置作为过渡起点
	_camera_look_at_pos = _get_camera_look_at_pos()
	camera_focus_target = target
	if target:
		add_message("相机锁定: " + target.name, Color(0.3, 0.8, 1))
	else:
		add_message("相机解锁", Color(0.7, 0.7, 0.7))

## 获取当前相机应观察的位置
func _get_camera_look_at_pos() -> Vector3:
	if camera_focus_target and is_instance_valid(camera_focus_target) and camera_focus_target.is_inside_tree():
		return camera_focus_target.global_position
	return global_position

## 清除相机锁定
func clear_camera_focus() -> void:
	set_camera_focus(null)

## 更新相机位置（球面坐标环绕），支持2s平滑过渡
func _update_camera() -> void:
	if not _camera:
		return
	var rad_az = deg_to_rad(_cam_azimuth)
	var rad_el = deg_to_rad(_cam_elevation)
	var offset = Vector3(
		_cam_distance * cos(rad_el) * sin(rad_az),
		_cam_distance * sin(rad_el),
		_cam_distance * cos(rad_el) * cos(rad_az)
	)
	
	# 计算期望的观察位置
	var desired_pos: Vector3
	if camera_focus_target and is_instance_valid(camera_focus_target) and camera_focus_target.is_inside_tree():
		desired_pos = camera_focus_target.global_position
	else:
		camera_focus_target = null
		desired_pos = global_position
	
	# 平滑插值到目标位置（指数衰减，约2秒完成86%过渡）
	var weight = 1.0 - exp(-get_process_delta_time())
	_camera_look_at_pos = _camera_look_at_pos.lerp(desired_pos, weight)
	
	_camera.global_position = _camera_look_at_pos + offset
	_camera.look_at(_camera_look_at_pos, Vector3.UP)

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
	
	# H键 - 重置相机到自身飞船
	if event is InputEventKey and event.pressed and event.keycode == KEY_H:
		clear_camera_focus()
		# 重置视角角度
		_cam_azimuth = 0.0
		_cam_elevation = 15.0
		_cam_distance = camera_default_distance
		add_message("相机复位", Color(0.3, 0.8, 1))
	
	# 右键拖拽 - 旋转视角（点击不执行任何操作）
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
	
	# 滚轮 - 往前滚拉远，往后滚拉近
	var zoom_step = camera_max_distance * 0.02
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_cam_distance = minf(camera_max_distance, _cam_distance + zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_cam_distance = maxf(camera_min_distance, _cam_distance - zoom_step)
