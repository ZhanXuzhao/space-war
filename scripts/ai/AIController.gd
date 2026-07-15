extends Node
class_name AIController

## NPC AI控制器 - 控制敌对/友好NPC飞船的行为
## 行为模式：巡逻、攻击、逃跑、采矿

enum AIState { IDLE, PATROL, ENGAGE, FLEE, MINE, RETURN }

@export var detection_range: float = 15000.0  # 探测范围
@export var engagement_range: float = 2000.0  # 接战距离
@export var orbit_range: float = 1500.0  # 环绕距离
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
	
	# 查找玩家
	await get_tree().process_frame
	_find_player()

func _find_player() -> void:
	var ships = get_tree().get_nodes_in_group("player_ship")
	if ships.size() > 0:
		player_ship = ships[0] as Ship

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
	
	_detect_hostiles()

## 交战状态
func _process_engage(delta: float) -> void:
	if not current_target or not current_target.is_alive:
		current_target = null
		current_state = AIState.PATROL
		return
	
	# 检查是否应该逃跑
	if owner_ship.get_shield_percent() < flee_shield_percent:
		current_state = AIState.FLEE
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

## 环绕目标飞行
func _orbit_target(delta: float) -> void:
	if not current_target:
		return
	
	orbit_angle += delta * 0.5  # 环绕速度
	
	var orbit_pos = current_target.global_position
	var offset = Vector3(
		cos(orbit_angle) * orbit_range,
		sin(orbit_angle * 0.3) * 100.0,  # 上下浮动
		sin(orbit_angle) * orbit_range
	)
	
	var target_pos = orbit_pos + offset
	owner_ship.order_move_to(target_pos)

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
