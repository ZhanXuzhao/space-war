extends CharacterBody3D
class_name Ship

## 飞船基类 - 包含所有飞船共有的属性和行为

signal shield_changed(current: float, max_value: float)
signal armor_changed(current: float, max_value: float)
signal hull_changed(current: float, max_value: float)
signal capacitor_changed(current: float, max_value: float)
signal ship_destroyed()
signal target_locked(target: Ship)
signal target_lost(target: Ship)

## 飞船基础属性
@export var ship_data: ShipData
@export var max_shield: float = 800.0
@export var max_armor: float = 600.0
@export var max_hull: float = 800.0
@export var max_capacitor: float = 400.0
@export var capacitor_recharge: float = 20.0  # 每秒恢复量
@export var max_speed: float = 1000.0
@export var acceleration: float = 100.0
@export var deceleration: float = 50.0
@export var rotation_speed: float = 2.0
@export var cargo_capacity: float = 500.0
@export var signature_radius: float = 40.0
@export var max_locked_targets: int = 8

## 当前状态
var current_shield: float
var current_armor: float
var current_hull: float
var current_capacitor: float
var current_speed: float = 0.0
var is_alive: bool = true

## 移动控制（由 PlayerShip 或 AI 驱动）
var has_move_order: bool = false
var move_target: Vector3 = Vector3.ZERO

## 持续靠近目标（非空时每帧更新 move_target，实现追踪移动目标）
var approach_target: Node3D = null
## 靠近停止距离（进入此范围后停止推进，避免贴脸抖动）
@export var approach_range: float = 500.0

## 速度指令模式（用于环绕时径向/切向速度分配）
var has_velocity_order: bool = false
var velocity_setpoint: Vector3 = Vector3.ZERO

## 目标与战斗
var locked_targets: Array[Ship] = []
var active_target: Ship = null
var target_lock_progress: float = 0.0  # 0.0 ~ 1.0
var is_target_locking: bool = false
var current_targeting_range: float = 20000.0  # 锁定距离

## 模块与武器
var high_slot_modules: Array[Node] = []
var mid_slot_modules: Array[Node] = []
var low_slot_modules: Array[Node] = []
var weapon_nodes: Array[Node] = []

## 防重复初始化标记（脚本热替换时使用）
var _initialized: bool = false

## 速度箭头
var _velocity_arrow: MeshInstance3D

## 船头标记圆球（在场景中定义，代码仅控制阵营颜色）
var _nose_sphere: MeshInstance3D

## 阵营
enum Faction { PLAYER, NPC_FRIENDLY, NPC_HOSTILE, NEUTRAL }
@export var faction: Faction = Faction.NEUTRAL

func _ready() -> void:
	if _initialized:
		return
	_initialized = true
	_init_stats()
	_setup_velocity_arrow()
	_setup_nose_color()

## 随机飞船名字池（按船型，由 ShipData.SHIP_CLASS_NAMES_POOL 管理）
## 公开接口：根据船型获取随机名字（供 EnemySpawner 等外部调用）
static func generate_random_name(ship_class: ShipData.ShipClass) -> String:
	return _get_random_name(ship_class)

func _init_stats() -> void:
	# 如果没有 ship_data，根据阵营自动生成一个合适船型的默认数据
	if not ship_data:
		ship_data = _create_default_ship_data()
	
	# 从 ship_data 应用属性到飞船
	_apply_ship_data()
	
	# 初始化当前值
	current_shield = max_shield
	current_armor = max_armor
	current_hull = max_hull
	current_capacitor = max_capacitor

## 根据阵营和船型生成默认 ShipData
func _create_default_ship_data() -> ShipData:
	var default_class: ShipData.ShipClass
	
	# NPC 敌对飞船随机分配船型（护卫舰/巡洋舰各半）
	if faction == Faction.NPC_HOSTILE:
		var roll = randf()
		if roll < 0.5:        # 50% 护卫舰
			default_class = ShipData.ShipClass.FRIGATE
		else:                  # 50% 巡洋舰
			default_class = ShipData.ShipClass.CRUISER
	else:
		default_class = ShipData.ShipClass.FRIGATE
	
	var data = ShipData.get_preset(default_class)
	data.ship_name = _get_random_name(data.ship_class)
	return data

## 将 ShipData 的属性应用到飞船的导出变量上
func _apply_ship_data() -> void:
	if not ship_data:
		return
	
	max_shield = ship_data.shield_hp
	max_armor = ship_data.armor_hp
	max_hull = ship_data.hull_hp
	max_capacitor = ship_data.capacitor_max
	capacitor_recharge = ship_data.capacitor_recharge_rate
	max_speed = ship_data.max_speed
	cargo_capacity = ship_data.cargo_capacity
	signature_radius = ship_data.signature_radius
	max_locked_targets = ship_data.max_locked_targets
	
	# 根据船型调整机动性
	match ship_data.ship_class:
		ShipData.ShipClass.FRIGATE:
			acceleration = 200.0
			deceleration = 100.0
			rotation_speed = 3.0
			approach_range = 300.0
		ShipData.ShipClass.CRUISER:
			acceleration = 80.0
			deceleration = 40.0
			rotation_speed = 1.5
			approach_range = 600.0
		ShipData.ShipClass.BATTLESHIP:
			acceleration = 30.0
			deceleration = 15.0
			rotation_speed = 0.6
			approach_range = 1000.0
	
	# 应用模型缩放
	_apply_model_scale()

## 根据 ship_data.model_scale 缩放飞船模型
## 场景中所有需要被缩放的视觉/物理节点应放在 ModelGroup 子节点下
func _apply_model_scale() -> void:
	if not ship_data:
		return
	var model_group = get_node_or_null("ModelGroup") as Node3D
	if model_group:
		model_group.scale = Vector3.ONE * ship_data.model_scale

static var _frigate_index: int = 0
static var _cruiser_index: int = 0
static var _battleship_index: int = 0

static func _get_random_name(ship_class: ShipData.ShipClass) -> String:
	var pool = ShipData.SHIP_CLASS_NAMES_POOL.get(ship_class, ShipData.SHIP_CLASS_NAMES_POOL[ShipData.ShipClass.FRIGATE])
	var idx: int
	match ship_class:
		ShipData.ShipClass.FRIGATE:
			idx = _frigate_index % pool.size()
			_frigate_index += 1
		ShipData.ShipClass.CRUISER:
			idx = _cruiser_index % pool.size()
			_cruiser_index += 1
		ShipData.ShipClass.BATTLESHIP:
			idx = _battleship_index % pool.size()
			_battleship_index += 1
		_:
			idx = _frigate_index % pool.size()
			_frigate_index += 1
	return pool[idx] + "级"

## 创建速度箭头（绿色锥体，方向朝前，长度随速度变化）
func _setup_velocity_arrow() -> void:
	var cone = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 5.0
	cone.height = 25.0
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 1.0, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(0.0, 1.0, 0.2)
	mat.emission_energy_multiplier = 0.5
	cone.material = mat
	
	_velocity_arrow = MeshInstance3D.new()
	_velocity_arrow.mesh = cone
	# ConeMesh 默认朝 +Y，旋转使其朝 -Z（飞船前进方向）
	_velocity_arrow.rotate_x(deg_to_rad(90.0))
	# 放在飞船前方（飞船长300m，前端在z=-150）
	_velocity_arrow.position.z = -180.0
	add_child(_velocity_arrow)

func _process(delta: float) -> void:
	if not is_alive:
		return
	_recharge_capacitor(delta)
	_update_velocity_arrow()
	_update_approach(delta)

## 更新速度箭头：速度越快箭头越长
func _update_velocity_arrow() -> void:
	if not _velocity_arrow:
		return
	var speed_ratio = clampf(current_speed / max_speed, 0.0, 1.0)
	# 最小为 0.1（静止时可见小点），最大为 1.0（全速）
	var scale_len = 0.1 + speed_ratio * 0.9
	_velocity_arrow.scale.z = scale_len
	_velocity_arrow.scale.x = 0.3 + speed_ratio * 0.7
	_velocity_arrow.scale.y = 0.3 + speed_ratio * 0.7
	_velocity_arrow.visible = speed_ratio > 0.01

## 设置船头圆球颜色（按阵营，圆球本身在场景中定义）
func _setup_nose_color() -> void:
	_nose_sphere = get_node_or_null("NoseSphere") as MeshInstance3D
	if not _nose_sphere:
		return
	
	var mat = _nose_sphere.get_surface_override_material(0)
	if not mat:
		mat = StandardMaterial3D.new()
		_nose_sphere.set_surface_override_material(0, mat)
	
	mat.emission_enabled = true
	mat.emission_energy_multiplier = 1.5
	match faction:
		Faction.PLAYER:
			mat.albedo_color = Color(0.2, 0.6, 1.0)
			mat.emission = Color(0.2, 0.6, 1.0)
		Faction.NPC_HOSTILE:
			mat.albedo_color = Color(1.0, 0.2, 0.1)
			mat.emission = Color(1.0, 0.2, 0.1)
		Faction.NPC_FRIENDLY:
			mat.albedo_color = Color(0.2, 1.0, 0.3)
			mat.emission = Color(0.2, 1.0, 0.3)
		_:  # NEUTRAL
			mat.albedo_color = Color(0.8, 0.8, 0.8)
			mat.emission = Color(0.8, 0.8, 0.8)

func _physics_process(delta: float) -> void:
	if not is_alive:
		return
	_handle_movement(delta)

## 基础移动逻辑（所有飞船共用，PlayerShip 可覆写增强）
func _handle_movement(delta: float) -> void:
	if has_velocity_order:
		# 速度指令模式：面向速度方向并加速到目标速度
		var target_speed = velocity_setpoint.length()
		if target_speed > 0.01:
			var target_dir = velocity_setpoint / target_speed
			var target_basis = Basis.looking_at(target_dir, Vector3.UP)
			global_basis = global_basis.slerp(target_basis, rotation_speed * delta)
			current_speed = move_toward(current_speed, target_speed, acceleration * delta)
		else:
			current_speed = move_toward(current_speed, 0.0, deceleration * delta)
		velocity = -global_basis.z * current_speed
	elif has_move_order:
		var direction = (move_target - global_position).normalized()
		var distance = global_position.distance_to(move_target)
		
		# 飞船朝向目标方向旋转（平滑旋转）
		var target_basis = Basis.looking_at(direction, Vector3.UP)
		global_basis = global_basis.slerp(target_basis, rotation_speed * delta)
		
		# 接近目标时减速
		var speed_factor = 1.0
		if distance < 200.0:
			speed_factor = distance / 200.0
		# 持续靠近模式下不自动停止
		if distance < 50.0 and not approach_target:
			has_move_order = false
		
		# 防超出：如果这一帧会飞过目标，直接归位
		var move_this_frame = current_speed * delta
		if move_this_frame > distance and distance > 0.01:
			global_position = move_target
			current_speed = 0.0
			velocity = Vector3.ZERO
			has_move_order = false
		else:
			current_speed = move_toward(current_speed, max_speed * speed_factor, acceleration * delta)
			velocity = -global_basis.z * current_speed
	else:
		# 减速
		current_speed = move_toward(current_speed, 0.0, deceleration * delta)
		velocity = -global_basis.z * current_speed
	
	move_and_slide()

func _recharge_capacitor(delta: float) -> void:
	if current_capacitor < max_capacitor:
		current_capacitor = minf(max_capacitor, current_capacitor + capacitor_recharge * delta)
		capacitor_changed.emit(current_capacitor, max_capacitor)

## 受到伤害
func take_damage(damage: float, _damage_type: String, _attacker: Node) -> void:
	if not is_alive:
		return
	
	var remaining = damage
	
	# 护盾吸收
	if current_shield > 0:
		var shield_damage = minf(current_shield, remaining)
		current_shield -= shield_damage
		remaining -= shield_damage
		shield_changed.emit(current_shield, max_shield)
	
	# 装甲吸收
	if remaining > 0 and current_armor > 0:
		var armor_damage = minf(current_armor, remaining)
		current_armor -= armor_damage
		remaining -= armor_damage
		armor_changed.emit(current_armor, max_armor)
	
	# 结构伤害
	if remaining > 0:
		current_hull -= remaining
		hull_changed.emit(current_hull, max_hull)
		if current_hull <= 0:
			_destroy()

func _destroy() -> void:
	is_alive = false
	ship_destroyed.emit()
	# 爆炸效果
	_spawn_explosion()
	queue_free()

func _spawn_explosion() -> void:
	# 简单的爆炸粒子效果 - 可通过场景扩展
	pass

## 锁定目标
func lock_target(target: Ship) -> bool:
	if not target.is_alive:
		return false
	# 清理已失效的锁定目标引用
	_cleanup_locked_targets()
	if locked_targets.size() >= max_locked_targets:
		return false
	if target in locked_targets:
		return true
	
	var distance = global_position.distance_to(target.global_position)
	if distance > current_targeting_range:
		return false
	
	locked_targets.append(target)
	target_locked.emit(target)
	return true

func unlock_target(target: Ship) -> void:
	locked_targets.erase(target)
	if active_target == target:
		active_target = null
	target_lost.emit(target)

## 清理已失效的锁定目标（被摧毁/freed 的引用）
func _cleanup_locked_targets() -> void:
	locked_targets = locked_targets.filter(func(t): return is_instance_valid(t) and t.is_alive)

func set_active_target(target: Ship) -> void:
	if target in locked_targets:
		active_target = target

## 持续靠近目标（每帧更新 move_target = target.global_position，实现追击）
func order_approach(target: Node3D) -> void:
	if not target or not is_instance_valid(target):
		return
	approach_target = target
	move_target = target.global_position
	has_move_order = true
	has_velocity_order = false

## 取消持续靠近
func cancel_approach() -> void:
	approach_target = null

## 每帧更新靠近目标位置（进入 approach_range 后停止推进，避免贴脸抖动）
func _update_approach(_delta: float) -> void:
	if not approach_target or not is_instance_valid(approach_target):
		approach_target = null
		return
	var dist = global_position.distance_to(approach_target.global_position)
	if dist < approach_range:
		# 计算刹车距离：v² / (2 * deceleration)，防止高速时太早取消导致冲出太远
		var stopping_dist = (current_speed * current_speed) / (2.0 * maxf(deceleration, 1.0))
		if dist < stopping_dist:
			# 已进入刹车区 → 取消靠近，减速滑停
			approach_target = null
			has_move_order = false
			return
		# 距离足够宽裕，继续靠近
	move_target = approach_target.global_position

## 移动到目标位置（基类实现，PlayerShip 可覆写）
func order_move_to(position: Vector3) -> void:
	approach_target = null
	move_target = position
	has_move_order = true
	has_velocity_order = false

## 速度指令模式：直接指定目标速度向量（用于环绕径向/切向分配）
func order_set_velocity(target_velocity: Vector3) -> void:
	has_velocity_order = true
	has_move_order = false
	velocity_setpoint = target_velocity

## 使用电容
func use_capacitor(amount: float) -> bool:
	if current_capacitor >= amount:
		current_capacitor -= amount
		capacitor_changed.emit(current_capacitor, max_capacitor)
		return true
	return false

## 获取信息
func get_hull_percent() -> float:
	return current_hull / max_hull * 100.0

func get_armor_percent() -> float:
	return current_armor / max_armor * 100.0

func get_shield_percent() -> float:
	return current_shield / max_shield * 100.0

func get_capacitor_percent() -> float:
	return current_capacitor / max_capacitor * 100.0

# ---------------------------------------------------------------------------
# 环绕轨迹可视化
# ---------------------------------------------------------------------------
var _trajectory_instance: MeshInstance3D = null

## 显示环绕轨迹圆环（围绕目标，水平面上的圆形）
func show_orbit_trajectory(radius: float = 1200.0, color: Color = Color(0.3, 0.8, 1.0)) -> void:
	if not _trajectory_instance:
		_trajectory_instance = MeshInstance3D.new()
		_trajectory_instance.name = "OrbitTrajectory"
		add_child(_trajectory_instance)

	# 用 SurfaceTool 构建线条网格（水平圆形）
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)

	var segments = 64
	for i in range(segments):
		var t1 = (2.0 * PI * i) / segments
		var t2 = (2.0 * PI * (i + 1)) / segments

		var p1 = Vector3(cos(t1) * radius, 0.0, sin(t1) * radius)
		var p2 = Vector3(cos(t2) * radius, 0.0, sin(t2) * radius)

		st.add_vertex(p1)
		st.add_vertex(p2)

	var mesh = st.commit()

	# 发光半透明材质
	var mat = ORMMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.5)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.2
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.surface_set_material(0, mat)

	_trajectory_instance.mesh = mesh
	_trajectory_instance.visible = true

## 隐藏环绕轨迹
func hide_orbit_trajectory() -> void:
	if _trajectory_instance:
		_trajectory_instance.visible = false

## 切换环绕轨迹显示
func toggle_orbit_trajectory(visible: bool, radius: float = 1200.0) -> void:
	if visible:
		show_orbit_trajectory(radius)
	else:
		hide_orbit_trajectory()
