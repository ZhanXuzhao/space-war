extends Node

## 全局游戏状态管理 - EVE风格单机版
## 管理玩家数据、经济、任务等全局状态

signal isk_changed(value: int)
signal location_changed(location_name: String)
signal combat_log(message: String, color: Color)

var player_isk: int = 50000:
	set(value):
		player_isk = value
		isk_changed.emit(player_isk)

var player_location: String = "加达里星门":
	set(value):
		player_location = value
		location_changed.emit(player_location)

var player_ship_data: Dictionary = {}
var player_cargo: Dictionary = {}  # {item_id: quantity}
var player_skills: Dictionary = {}  # {skill_name: level}
var known_stations: Array[String] = []
var kill_count: int = 0
var mining_yield_total: int = 0

func _ready() -> void:
	init_player_data()

var player_ship_class: ShipData.ShipClass = ShipData.ShipClass.BATTLESHIP
var player_ship_data_resource: ShipData = null  # 当前玩家的 ShipData 资源

func init_player_data() -> void:
	# 使用 ShipData 预设初始化玩家数据
	player_ship_class = ShipData.ShipClass.BATTLESHIP
	player_ship_data_resource = ShipData.get_preset(player_ship_class)
	
	player_ship_data = {
		"name": player_ship_data_resource.ship_name,
		"ship_class": player_ship_class,
		"hull_max": player_ship_data_resource.hull_hp,
		"armor_max": player_ship_data_resource.armor_hp,
		"shield_max": player_ship_data_resource.shield_hp,
		"capacitor_max": player_ship_data_resource.capacitor_max,
		"capacitor_recharge": player_ship_data_resource.capacitor_recharge_rate,
		"max_speed": player_ship_data_resource.max_speed,
		"warp_speed": player_ship_data_resource.warp_speed,
		"mass": player_ship_data_resource.mass,
		"cargo_capacity": player_ship_data_resource.cargo_capacity,
		"drone_bay": player_ship_data_resource.drone_bay,
		"max_locked_targets": player_ship_data_resource.max_locked_targets,
		"max_turret_hardpoints": player_ship_data_resource.turret_hardpoints,
		"max_launcher_hardpoints": player_ship_data_resource.launcher_hardpoints,
		"low_slots": player_ship_data_resource.low_slots,
		"mid_slots": player_ship_data_resource.mid_slots,
		"high_slots": player_ship_data_resource.high_slots
	}
	
	# 初始物品
	player_cargo = {
		"三钛合金": 200,
		"同位素": 50
	}

	player_skills = {
		"飞船操控学": 1,
		"护盾操作": 1,
		"装甲操作": 1,
		"导航学": 1,
		"炮术": 1,
		"采矿技术": 1
	}

## 添加物品到货舱
func add_to_cargo(item_name: String, quantity: float) -> void:
	var current = player_cargo.get(item_name, 0.0)
	player_cargo[item_name] = current + int(quantity)

## 从货舱移除物品
func remove_from_cargo(item_name: String, quantity: int) -> bool:
	var current = player_cargo.get(item_name, 0)
	if current < quantity:
		return false
	player_cargo[item_name] = current - quantity
	if player_cargo[item_name] <= 0:
		player_cargo.erase(item_name)
	return true

## 获取货舱容量使用情况
func get_cargo_used() -> int:
	var total = 0
	for qty in player_cargo.values():
		total += qty
	return total

## 飞船场景路径映射（ShipClass → 场景文件路径）
const PLAYER_SHIP_SCENES := {
	ShipData.ShipClass.FRIGATE: "res://scenes/player/Frigate.tscn",
	ShipData.ShipClass.CRUISER: "res://scenes/player/Cruiser.tscn",
	ShipData.ShipClass.BATTLESHIP: "res://scenes/player/Battleship.tscn",
}

## 根据船型获取玩家飞船场景
func get_player_ship_scene(cls: ShipData.ShipClass) -> PackedScene:
	var path = PLAYER_SHIP_SCENES.get(cls, PLAYER_SHIP_SCENES[ShipData.ShipClass.BATTLESHIP])
	return load(path)

## 在场景中生成玩家飞船
func spawn_player_ship() -> Node3D:
	var scene = get_player_ship_scene(player_ship_class)
	var ship = scene.instantiate()
	# 预设置船型数据（在 _ready 前生效）
	ship.ship_data = player_ship_data_resource
	# 将脚本替换为 PlayerShip.gd（增加玩家专用功能：摄像机、交互控制、模块管理）
	ship.set_script(preload("res://scripts/ships/PlayerShip.gd"))
	# 添加到玩家组
	ship.add_to_group("player_ship")
	return ship

## 更换玩家飞船类型（带场景切换）
func change_player_ship(new_class: ShipData.ShipClass) -> void:
	player_ship_class = new_class
	player_ship_data_resource = ShipData.get_preset(new_class)
	
	player_ship_data = {
		"name": player_ship_data_resource.ship_name,
		"ship_class": int(new_class),
		"hull_max": player_ship_data_resource.hull_hp,
		"armor_max": player_ship_data_resource.armor_hp,
		"shield_max": player_ship_data_resource.shield_hp,
		"capacitor_max": player_ship_data_resource.capacitor_max,
		"capacitor_recharge": player_ship_data_resource.capacitor_recharge_rate,
		"max_speed": player_ship_data_resource.max_speed,
		"warp_speed": player_ship_data_resource.warp_speed,
		"mass": player_ship_data_resource.mass,
		"cargo_capacity": player_ship_data_resource.cargo_capacity,
		"drone_bay": player_ship_data_resource.drone_bay,
		"max_locked_targets": player_ship_data_resource.max_locked_targets,
		"max_turret_hardpoints": player_ship_data_resource.turret_hardpoints,
		"max_launcher_hardpoints": player_ship_data_resource.launcher_hardpoints,
		"low_slots": player_ship_data_resource.low_slots,
		"mid_slots": player_ship_data_resource.mid_slots,
		"high_slots": player_ship_data_resource.high_slots
	}
	
	# 触发场景中飞船替换（如果场景已加载）
	var root = Engine.get_main_loop().root
	var space_war = root.get_node_or_null("/root/SpaceWar")
	if space_war:
		var old_ship = space_war.get_node_or_null("PlayerShip")
		if old_ship:
			var new_ship = spawn_player_ship()
			new_ship.name = "PlayerShip"
			new_ship.global_transform = old_ship.global_transform
			space_war.add_child(new_ship)
			old_ship.queue_free()
			# 通知 HUD 更新引用
			var hud = space_war.get_node_or_null("HUD")
			if hud and hud.has_method("on_player_ship_changed"):
				hud.on_player_ship_changed(new_ship)
	
	isk_changed.emit(player_isk)
