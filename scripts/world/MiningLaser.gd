extends Node3D
class_name MiningLaser

## 采矿激光 - 用于开采小行星

@export var mining_power: float = 50.0  # 每秒开采量
@export var mining_range: float = 5000.0  # 采矿距离
@export var capacitor_usage: float = 5.0

var is_active: bool = false
var current_target: Asteroid = null
var owner_ship: Ship
var mining_timer: float = 0.0

func _ready() -> void:
	owner_ship = get_parent() as Ship

func _process(delta: float) -> void:
	if not is_active or not current_target:
		return
	if not current_target.is_inside_tree():
		current_target = null
		return
	
	var dist = owner_ship.global_position.distance_to(current_target.global_position)
	if dist > mining_range:
		return
	
	mining_timer += delta
	if mining_timer >= 1.0:  # 每秒开采一次
		mining_timer = 0.0
		if owner_ship.use_capacitor(capacitor_usage):
			var mined = await current_target.mine(mining_power)
			if mined > 0:
				var ore_value = current_target.ore_type
				# 添加到货舱 - 通过Autoload访问
				if has_node("/root/Global"):
					var g = get_node("/root/Global")
					if g.has_method("add_to_cargo"):
						g.add_to_cargo(ore_value, mined)

func start_mining(asteroid: Asteroid) -> void:
	if not asteroid or asteroid.is_depleted:
		return
	current_target = asteroid
	is_active = true

func stop_mining() -> void:
	is_active = false
	current_target = null
