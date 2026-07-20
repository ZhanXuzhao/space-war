extends Node
class_name EnemySpawner

## 敌方飞船生成器 - 在太空中随机生成敌对NPC飞船
## 附带船型分布控制，可配置护卫舰/巡洋舰/战列舰的生成比例

signal enemy_spawned(enemy: Ship)

@export var spawn_distance_min: float = 10000.0  # 最小生成距离（距玩家）
@export var spawn_distance_max: float = 30000.0 # 最大生成距离（距玩家）
@export var wave_size: int = 1                 # 每波召唤数量
@export var enable_warp_effect: bool = true     # 是否启用跃迁入场效果

## 飞船场景映射（共用场景，敌我同模）
const NPC_SHIP_SCENES := {
	ShipData.ShipClass.FRIGATE: preload("res://scenes/ships/Frigate.tscn"),
	ShipData.ShipClass.CRUISER: preload("res://scenes/ships/Cruiser.tscn"),
	ShipData.ShipClass.BATTLESHIP: preload("res://scenes/ships/Battleship.tscn"),
}

# 船型分布权重（总和不必为1）
@export var frigate_weight: float = 1.0
@export var cruiser_weight: float = 1.0
@export var battleship_weight: float = 1.0

var player_ship: Ship = null
var current_enemies: Array[Ship] = []

func _ready() -> void:
	# 等待一帧确保场景完全加载
	await get_tree().process_frame
	_find_player()
	
	# 如果还没找到，再等几帧后重试
	if not player_ship:
		await get_tree().create_timer(0.5).timeout
		_find_player()
	
	# 游戏开始时不生成敌人（可通过按钮手动召唤）
	print("EnemySpawner: 就绪，共用场景模式已启用")

func _find_player() -> void:
	var ships = get_tree().get_nodes_in_group("player_ship")
	if ships.size() > 0:
		player_ship = ships[0] as Ship
	if not player_ship:
		player_ship = get_node_or_null("/root/SpaceWar/PlayerShip") as Ship

func _process(_delta: float) -> void:
	# 仅用于持续查找玩家（手动召唤时需要玩家位置）
	if not player_ship or not is_instance_valid(player_ship):
		_find_player()
	# 清理已销毁的敌人
	_cleanup_destroyed()

func _cleanup_destroyed() -> void:
	current_enemies = current_enemies.filter(func(e): return is_instance_valid(e) and e.is_alive)

## 根据权重随机选择船型
func _pick_ship_class() -> ShipData.ShipClass:
	var total = frigate_weight + cruiser_weight + battleship_weight
	if total <= 0:
		return ShipData.ShipClass.FRIGATE
	var roll = randf() * total
	if roll < frigate_weight:
		return ShipData.ShipClass.FRIGATE
	elif roll < frigate_weight + cruiser_weight:
		return ShipData.ShipClass.CRUISER
	else:
		return ShipData.ShipClass.BATTLESHIP

func _try_spawn_enemy() -> void:
	_try_spawn_class(_pick_ship_class())

## 生成指定船型的敌舰
func _try_spawn_class(ship_class: ShipData.ShipClass) -> void:
	if not player_ship or not is_instance_valid(player_ship):
		return
	
	var ship_scene = NPC_SHIP_SCENES.get(ship_class, NPC_SHIP_SCENES[ShipData.ShipClass.FRIGATE])
	var enemy = ship_scene.instantiate() as Ship
	if not enemy:
		print("EnemySpawner: 实例化NPC失败!")
		return
	
	# 球坐标系随机位置（以玩家为中心）
	var r = randf_range(spawn_distance_min, spawn_distance_max)   # 半径 5km-10km
	var theta = randf_range(-PI / 2.0, PI / 2.0)                 # 纬度（-90° ~ 90°）
	var phi = randf() * 2.0 * PI                                 # 经度（0° ~ 360°）
	
	var spawn_pos = player_ship.global_position + Vector3(
		r * cos(theta) * cos(phi),
		r * sin(theta),
		r * cos(theta) * sin(phi)
	)
	
	# 设置阵营和船型
	enemy.faction = Ship.Faction.NPC_HOSTILE
	# 预设置 ship_data，覆盖 Ship._ready() 中的随机分配
	var preset = ShipData.get_preset(ship_class)
	preset.ship_name = Ship.generate_random_name(ship_class)
	enemy.ship_data = preset
	
	# 动态添加 AI 控制器（共用场景中不包含此节点）
	if not enemy.get_node_or_null("AIController"):
		var ai = Node.new()
		ai.name = "AIController"
		ai.set_script(preload("res://scripts/ai/AIController.gd"))
		ai.detection_range = 20000.0
		ai.engagement_range = 5000.0
		ai.orbit_range = 4000.0
		ai.flee_shield_percent = 25.0
		ai.aggro_chance = 1.0
		enemy.add_child(ai)
	
	# 先将敌人置于 spawn_pos 再添加到场景树
	enemy.transform.origin = spawn_pos
	get_tree().current_scene.add_child(enemy)
	# 再强制同步一次全局位置
	enemy.global_position = spawn_pos
	
	current_enemies.append(enemy)
	enemy_spawned.emit(enemy)
	print("EnemySpawner: 生成[%s] 位置=" % ShipData.SHIP_CLASS_NAMES.get(ship_class, "?"), spawn_pos, " 当前敌舰数=", current_enemies.size())
	
	# 跃迁入场效果（按船型缩放入场光效大小）
	if enable_warp_effect:
		_start_warp_effect(spawn_pos, ship_class)

func _start_warp_effect(pos: Vector3, ship_class: ShipData.ShipClass = ShipData.ShipClass.FRIGATE) -> void:
	# 按船型决定光效大小
	var size = 15.0
	match ship_class:
		ShipData.ShipClass.CRUISER:
			size = 40.0
		ShipData.ShipClass.BATTLESHIP:
			size = 80.0
	
	var warp_marker = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = size
	sphere.height = size * 2.0
	sphere.material = StandardMaterial3D.new()
	sphere.material.albedo_color = Color(0.3, 0.6, 1.0, 0.6)
	sphere.material.emission_enabled = true
	sphere.material.emission = Color(0.3, 0.6, 1.0, 1)
	warp_marker.mesh = sphere
	get_tree().current_scene.add_child(warp_marker)
	warp_marker.global_position = pos
	
	# 渐隐动画
	var tween = create_tween()
	tween.tween_property(warp_marker, "scale", Vector3(3, 3, 3), 0.8)
	tween.parallel().tween_property(warp_marker.mesh, "material:albedo_color:a", 0.0, 0.8)
	tween.tween_callback(warp_marker.queue_free)

## 手动召唤一波敌人（由按钮触发，无数量上限）
func spawn_wave(count: int = -1) -> void:
	if count < 0:
		count = wave_size
	print("EnemySpawner: 召唤一波敌舰 x", count)
	for i in range(count):
		_try_spawn_enemy()

## 清理所有敌人
func clear_all_enemies() -> void:
	for enemy in current_enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	current_enemies.clear()

## 获取当前敌人数量
func get_enemy_count() -> int:
	_cleanup_destroyed()
	return current_enemies.size()
