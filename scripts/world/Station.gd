extends Node3D
class_name Station

## 空间站 - 停靠、交易、修理

signal player_docked(station: Station)
signal player_undocked(station: Station)

@export var station_name: String = "加达里主星 - 8号星域"
@export var station_type: String = "贸易站"
@export var docking_range: float = 500.0

var is_player_docked: bool = false
var player_ship_ref: Ship = null

# 空间站服务
var has_market: bool = true
var has_repair: bool = true
var has_refitting: bool = true

func _ready() -> void:
	add_to_group("stations")

## 检测玩家停靠
func check_docking(ship: Ship) -> void:
	if is_player_docked:
		return
	
	var dist = global_position.distance_to(ship.global_position)
	if dist < docking_range:
		dock_player(ship)

func dock_player(ship: Ship) -> void:
	is_player_docked = true
	player_ship_ref = ship
	ship.visible = false  # 停靠时隐藏飞船
	player_docked.emit(self)

func undock_player() -> void:
	if not is_player_docked:
		return
	is_player_docked = false
	if player_ship_ref:
		player_ship_ref.visible = true
		# 将玩家放置在空间站出口
		player_ship_ref.global_position = global_position + Vector3(0, 0, 1000)
	player_undocked.emit(self)
	player_ship_ref = null
