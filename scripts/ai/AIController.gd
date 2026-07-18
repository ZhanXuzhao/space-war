extends Node
class_name AIController

## NPC AI控制器 - 控制敌对/友好NPC飞船的行为
## 行为模式：巡逻、攻击、逃跑、采矿

enum AIState { IDLE, PATROL, ENGAGE, FLEE, MINE, RETURN }

@export var detection_range: float = 15000.0  # 探测范围
@export var engagement_range: float = 2000.0  # 接战距离
@export var orbit_range: float = 1200.0  # 环绕距离 = 武器射程 1500m × 80%
@export var flee_shield_percent: float = 25.0  # 逃跑护盾阈值
@export var patrol_points: Array[Vector3] = []
@export var aggro_chance: float = 0.8  # 主动攻击概率

var current_state: AIState = AIState.IDLE
var owner_ship: Ship
var current_target: Ship = null
var patrol_index: int = 0
var state_timer: float = 0.0
var player_ship: Ship = null
var orbit_angle: float = 0.0

func _ready() -> void:
	owner_ship = get_parent() as Ship
	if owner_ship and owner_ship.faction == Ship.Faction.NPC_HOSTILE:
		current_state = AIState.PATROL
		# 根据船型调整AI战斗参数
		_adjust_for_ship_class()
		# 武器由 Ship._create_default_equipment() 自动创建
	
	# 查找玩家
	await get_tree().process_frame
	_find_player()
	
	# 延迟设置巡逻点
	await get_tree().create_timer(0.5).timeout
	_setup_auto_patrol()

## 根据船型调整AI战斗参数
func _adjust_for_ship_class() -> void:
	if not owner_ship or not owner_ship.ship_data:
		return
	match owner_ship.ship_data.ship_class:
		ShipData.ShipClass.FRIGATE:
			detection_range = 20000.0
			engagement_range = 5000.0   # 小型武器射程
			orbit_range = 4000.0        # 80% 射程
		ShipData.ShipClass.CRUISER:
			detection_range = 30000.0
			engagement_range = 10000.0  # 中型武器射程
			orbit_range = 8000.0
			flee_shield_percent = 20.0
		ShipData.ShipClass.BATTLESHIP:
			detection_range = 40000.0
			engagement_range = 20000.0  # 大型武器射程
			orbit_range = 16000.0
			flee_shield_percent = 15.0

func _setup_auto_patrol() -> void:
	if not owner_ship or patrol_points.size() > 0:
		return
	# 自动创建巡逻点
	var center = owner_ship.global_position
	for i in range(4):
		var angle = (2.0 * PI * i) / 4
		var point = center + Vector3(cos(angle) * 2000.0, 0, sin(angle) * 2000.0)
		patrol_points.append(point)

func _find_player() -> void:
	var ships = get_tree().get_nodes_in_group("player_ship")
	if ships.size() > 0:
		player_ship = ships[0] as Ship
	if not player_ship:
		player_ship = get_node_or_null("/root/SpaceWar/PlayerShip") as Ship

func _process(delta: float) -> void:
	if not owner_ship or not owner_ship.is_alive:
		return
	
	state_timer -= delta
	
	match current_state:
		AIState.IDLE:
			_process_idle(delta)
		AIState.PATROL:
			_process_patrol(delta)
		AIState.ENGAGE:
			_process_engage(delta)
		AIState.FLEE:
			_process_flee(delta)

func _physics_process(delta: float) -> void:
	if not owner_ship or not owner_ship.is_alive:
		return
	owner_ship._handle_movement(delta)

## 空闲状态
func _process_idle(_delta: float) -> void:
	if state_timer <= 0:
		current_state = AIState.PATROL
		state_timer = 5.0
	_detect_hostiles()

## 巡逻状态
func _process_patrol(_delta: float) -> void:
	if patrol_points.size() == 0:
		# 没有巡逻点时随机移动
		if state_timer <= 0:
			owner_ship.has_move_order = false
			state_timer = 3.0
		return
	
	# 移动到下一个巡逻点
	var target_point = patrol_points[patrol_index]
	var dist = owner_ship.global_position.distance_to(target_point)
	if dist < 100.0:
		patrol_index = (patrol_index + 1) % patrol_points.size()
		owner_ship.order_move_to(patrol_points[patrol_index])
	
	# 持续探测玩家
	_detect_hostiles()
	
	# 如果没有巡逻点移动指令，设置第一个巡逻点
	if not owner_ship.has_move_order and patrol_points.size() > 0:
		owner_ship.order_move_to(patrol_points[0])

## 交战状态
func _process_engage(delta: float) -> void:
	if not current_target or not current_target.is_alive:
		current_target = null
		current_state = AIState.PATROL
		return
	
	# 锁定目标
	if current_target not in owner_ship.locked_targets:
		owner_ship.lock_target(current_target)
	owner_ship.set_active_target(current_target)
	
	# 环绕目标飞行
	_orbit_target(delta)
	
	# 射击
	_fire_weapons(delta)

## 逃跑状态
func _process_flee(_delta: float) -> void:
	var flee_direction = Vector3.RIGHT
	if current_target:
		flee_direction = (owner_ship.global_position - current_target.global_position).normalized()
	
	var flee_point = owner_ship.global_position + flee_direction * 10000.0
	owner_ship.order_move_to(flee_point)
	
	# 护盾恢复后停止逃跑
	if owner_ship.get_shield_percent() > 60.0:
		current_state = AIState.PATROL

## 探测敌对目标
func _detect_hostiles() -> void:
	if not player_ship or not player_ship.is_alive:
		return
	
	var dist = owner_ship.global_position.distance_to(player_ship.global_position)
	if dist < detection_range:
		if randf() < aggro_chance:
			current_target = player_ship
			current_state = AIState.ENGAGE
			owner_ship.lock_target(current_target)

## 三维环绕目标飞行（径向+切向速度分配优化）
## 原理：将速度分解为径向（朝向/远离目标）和切向（环绕）分量
## - 距离过远/过近时，径向分量优先，快速修正距离
## - 距离适当时，切向分量为主，维持稳定环绕
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
	
	# 径向方向（从飞船指向目标）
	var radial_dir = to_target / distance
	
	# 切向方向（与径向垂直，在水平面上）
	var tangential_dir = radial_dir.cross(Vector3.UP)
	if tangential_dir.length() < 0.01:
		tangential_dir = Vector3.RIGHT
	tangential_dir = tangential_dir.normalized()
	
	# 垂直方向（与径向和切向都垂直，产生立体轨迹）
	var vertical_dir = radial_dir.cross(tangential_dir).normalized()
	
	var max_speed = owner_ship.max_speed
	var distance_error = distance - orbit_range
	var abs_error = abs(distance_error)
	var dead_zone = orbit_range * 0.2  # 20% 死区
	
	# ===== 径向速度：根据距离误差分配 =====
	# 距离误差越大，径向分配越多，以快速修正距离
	var radial_speed = 0.0
	if abs_error > dead_zone:
		# 超出死区：径向优先，全力修正距离
		var factor = minf(abs_error / (orbit_range * 0.5), 1.0)
		radial_speed = sign(distance_error) * max_speed * factor
	else:
		# 在死区内：温和的径向修正
		radial_speed = distance_error * 0.3
	
	# ===== 切向速度：维持环绕运动 =====
	# 距离偏差越大，切向分配越少（让路给径向修正）
	var radial_factor = minf(abs_error / maxf(dead_zone, 1.0), 1.0)
	var tangential_speed = max_speed * 0.6 * (1.0 - radial_factor * 0.8)
	
	# ===== 垂直速度：立体起伏轨迹 =====
	var vertical_speed = sin(orbit_angle * 0.7) * max_speed * 0.2
	
	# ===== 合成最终速度向量 =====
	var final_velocity = (
		radial_dir * radial_speed +
		tangential_dir * tangential_speed +
		vertical_dir * vertical_speed
	)
	
	owner_ship.order_set_velocity(final_velocity)

## 射击武器
func _fire_weapons(delta: float) -> void:
	if not current_target:
		return
	for weapon in owner_ship.weapon_nodes:
		if weapon is Weapon:
			weapon.try_fire(current_target, delta)

## 设置巡逻点
func setup_patrol(center: Vector3, radius: float, point_count: int = 4) -> void:
	patrol_points.clear()
	for i in range(point_count):
		var angle = (2.0 * PI * i) / point_count
		var point = center + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		patrol_points.append(point)
