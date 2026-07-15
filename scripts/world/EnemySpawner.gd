extends Node
class_name EnemySpawner

## 敌方飞船生成器 - 在太空中随机生成敌对NPC飞船
## 会间隔随机时间在玩家周围生成敌方飞船，并有跃迁入场效果

signal enemy_spawned(enemy: Ship)

@export var spawn_interval_min: float = 15.0   # 最短生成间隔（秒）
@export var spawn_interval_max: float = 45.0   # 最长生成间隔（秒）
@export var spawn_distance_min: float = 5000.0  # 最小生成距离（距玩家）
@export var spawn_distance_max: float = 15000.0 # 最大生成距离（距玩家）
@export var max_enemies: int = 8               # 最大同时存在敌人数
@export var wave_size: int = 3                 # 每波召唤数量
@export var npc_scene: PackedScene             # NPC飞船场景
@export var enable_warp_effect: bool = true     # 是否启用跃迁入场效果

var player_ship: Ship = null
var current_enemies: Array[Ship] = []
var spawn_timer: float = 0.0
var next_spawn_time: float = 0.0
var is_active: bool = false

func _ready() -> void:
	# 等待一帧确保场景完全加载
	await get_tree().process_frame
	_find_player()
	
	# 如果还没找到，再等几帧后重试
	if not player_ship:
		await get_tree().create_timer(0.5).timeout
		_find_player()
	
	# 自动启动
	if npc_scene:
		start()
		print("EnemySpawner: 已启动，玩家=", player_ship, " 场景=", npc_scene.resource_path)
	
	# 开局立即生成第一波（等找到玩家后）
	if player_ship:
		_spawn_initial_wave()
	else:
		# 玩家还没找到，延迟后再生成
		await get_tree().create_timer(1.0).timeout
		if player_ship and is_active:
			_spawn_initial_wave()

func _find_player() -> void:
	var ships = get_tree().get_nodes_in_group("player_ship")
	if ships.size() > 0:
		player_ship = ships[0] as Ship
	if not player_ship:
		player_ship = get_node_or_null("/root/SpaceWar/PlayerShip") as Ship

func start() -> void:
	is_active = true
	set_process(true)

func stop() -> void:
	is_active = false
	set_process(false)

func _process(delta: float) -> void:
	if not is_active:
		return
	
	# 如果还没找到玩家飞船，持续尝试
	if not player_ship or not is_instance_valid(player_ship):
		_find_player()
		return
	
	if not player_ship.is_alive:
		return
	
	# 清理已销毁的敌人
	_cleanup_destroyed()
	
	spawn_timer += delta
	if spawn_timer >= next_spawn_time:
		spawn_timer = 0.0
		next_spawn_time = randf_range(spawn_interval_min, spawn_interval_max)
		_try_spawn_enemy()

func _cleanup_destroyed() -> void:
	current_enemies = current_enemies.filter(func(e): return is_instance_valid(e) and e.is_alive)

func _try_spawn_enemy() -> void:
	if current_enemies.size() >= max_enemies:
		return
	if not npc_scene:
		return
	if not player_ship or not is_instance_valid(player_ship):
		return
	
	var enemy = npc_scene.instantiate() as Ship
	if not enemy:
		print("EnemySpawner: 实例化NPC失败!")
		return
	
	# 随机位置（以玩家为中心，在水平面上随机角度和距离）
	var angle = randf() * 2.0 * PI
	var distance = randf_range(spawn_distance_min, spawn_distance_max)
	var height_offset = randf_range(-500.0, 500.0)
	
	var spawn_pos = player_ship.global_position + Vector3(
		cos(angle) * distance,
		height_offset,
		sin(angle) * distance
	)
	
	# 设置阵营
	enemy.faction = Ship.Faction.NPC_HOSTILE
	
	# 直接添加到场景树（_try_spawn_enemy 只在 _process/按钮中调用，此时场景已完全初始化）
	get_tree().current_scene.add_child(enemy)
	enemy.global_position = spawn_pos
	
	current_enemies.append(enemy)
	enemy_spawned.emit(enemy)
	print("EnemySpawner: 生成敌舰，位置=", spawn_pos, " 当前敌舰数=", current_enemies.size())
	
	# 跃迁入场效果
	if enable_warp_effect:
		_start_warp_effect(spawn_pos)

func _start_warp_effect(pos: Vector3) -> void:
	# 简单的光效指示
	var warp_marker = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 15.0
	sphere.height = 30.0
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

## 开局立即生成一波敌人
func _spawn_initial_wave() -> void:
	print("EnemySpawner: 开局生成第一波敌舰")
	next_spawn_time = 1.0  # 第一波后快速进入正常循环

## 手动召唤一波敌人（由按钮触发）
func spawn_wave(count: int = -1) -> void:
	if count < 0:
		count = wave_size
	# 计算剩余容量
	var available = max_enemies - _count_alive()
	var actual_count = mini(count, available)
	if actual_count <= 0:
		print("EnemySpawner: 已达最大敌舰数，无法召唤")
		return
	print("EnemySpawner: 召唤一波敌舰 x", actual_count)
	for i in range(actual_count):
		_try_spawn_enemy()

func _count_alive() -> int:
	var alive = 0
	for e in current_enemies:
		if is_instance_valid(e) and e.is_alive:
			alive += 1
	return alive

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
