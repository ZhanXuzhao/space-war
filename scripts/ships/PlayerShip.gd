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
var move_target: Vector3 = Vector3.ZERO
var has_move_order: bool = false
var warp_target: Vector3 = Vector3.ZERO
var warp_progress: float = 0.0
var warp_charge_time: float = 3.0
var warp_charging: bool = false
var angular_velocity: Vector3 = Vector3.ZERO

## 模块管理
var module_manager: Node

func _ready() -> void:
	super._ready()
	move_target = global_position
	module_manager = get_node_or_null("../ModuleManager")

func _process(delta: float) -> void:
	super._process(delta)
	
	match flight_mode:
		FlightMode.NORMAL:
			_process_normal_flight(delta)
		FlightMode.WARPING:
			_process_warp(delta)

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
	move_target = position
	has_move_order = true

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
