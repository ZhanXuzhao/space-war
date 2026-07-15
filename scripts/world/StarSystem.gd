extends Node3D
class_name StarSystem

## 星系管理器 - 管理星系中的所有对象

@export var system_name: String = "加达里星域"
@export var system_security: float = 0.8  # 0.0(0.0低安) ~ 1.0(高安)
@export var asteroid_count: int = 30
@export var npc_count: int = 5
@export var station_count: int = 1
@export var system_radius: float = 50000.0  # 星系大小

@export var asteroid_scene: PackedScene
@export var npc_scene: PackedScene
@export var station_scene: PackedScene

func _ready() -> void:
	_generate_system()

func _generate_system() -> void:
	_generate_asteroids()
	_generate_npcs()
	_generate_stations()

func _generate_asteroids() -> void:
	if not asteroid_scene:
		return
	
	var ore_types = ["三钛合金", "同位素", "克雷多", "杰斯贝"]
	
	for i in range(asteroid_count):
		var asteroid = asteroid_scene.instantiate() as Asteroid
		if asteroid:
			asteroid.ore_type = ore_types[randi() % ore_types.size()]
			
			# 随机位置（环形分布）
			var angle = randf() * 2.0 * PI
			var radius = randf_range(2000.0, system_radius * 0.8)
			var height = randf_range(-1000.0, 1000.0)
			asteroid.global_position = Vector3(
				cos(angle) * radius,
				height,
				sin(angle) * radius
			)
			
			add_child(asteroid)

func _generate_npcs() -> void:
	if not npc_scene:
		return
	
	for i in range(npc_count):
		var npc = npc_scene.instantiate() as Node3D
		if npc:
			var angle = randf() * 2.0 * PI
			var radius = randf_range(5000.0, system_radius * 0.6)
			npc.global_position = Vector3(
				cos(angle) * radius,
				randf_range(-200.0, 200.0),
				sin(angle) * radius
			)
			add_child(npc)

func _generate_stations() -> void:
	if not station_scene:
		return
	
	for i in range(station_count):
		var station = station_scene.instantiate() as Station
		if station:
			var angle = randf() * 2.0 * PI
			var radius = randf_range(3000.0, 5000.0)
			station.global_position = Vector3(
				cos(angle) * radius,
				0,
				sin(angle) * radius
			)
			station.station_name = system_name + " - 空间站 " + str(i + 1)
			add_child(station)

## 获取安全等级描述
func get_security_text() -> String:
	if system_security >= 0.9:
		return "高安全"
	elif system_security >= 0.5:
		return "中安全"
	elif system_security >= 0.1:
		return "低安全"
	else:
		return "0.0地区"
