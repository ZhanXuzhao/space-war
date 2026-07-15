extends Node

## 全局游戏状态管理 - EVE风格单机版
## 管理玩家数据、经济、任务等全局状态

signal isk_changed(value: int)
signal location_changed(location_name: String)

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
	# DEBUG: 延迟几帧后检查场景树
	get_tree().create_timer(0.1).timeout.connect(_debug_scene_tree)

func _debug_scene_tree() -> void:
	print("=== DEBUG: 场景树检查 ===")
	_dump_node(get_tree().root, 0)
	print("=== DEBUG: 结束 ===")

func _dump_node(node: Node, depth: int) -> void:
	var indent = ""
	for i in depth:
		indent += "  "
	var info = indent + node.name + " (" + node.get_class() + ")"
	if "instance" in node and node.get("instance") != null:
		info += " [INSTANCE]"
	print(info)
	for c in node.get_children():
		_dump_node(c, depth + 1)

func init_player_data() -> void:
	player_ship_data = {
		"name": "秃鹫级",
		"hull_max": 800,
		"armor_max": 600,
		"shield_max": 800,
		"capacitor_max": 400,
		"capacitor_recharge": 20.0,
		"max_speed": 280.0,
		"warp_speed": 3.0,
		"mass": 1200000,
		"cargo_capacity": 500,
		"drone_bay": 20,
		"max_locked_targets": 4,
		"max_turret_hardpoints": 3,
		"max_launcher_hardpoints": 1,
		"low_slots": 3,
		"mid_slots": 3,
		"high_slots": 4
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
