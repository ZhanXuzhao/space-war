extends Node

## 舰队管理器 - 管理所有舰队和玩家飞船
## 作为 Autoload 单例使用 (已在 project.godot 中注册)

const FleetClass = preload("res://scripts/fleet/Fleet.gd")

signal fleet_created(fleet_id: int)
signal fleet_deleted(fleet_id: int)
signal fleet_renamed(fleet_id: int, new_name: String)
signal ship_added_to_fleet(ship: Node, fleet_id: int)
signal ship_removed_from_fleet(ship: Node, fleet_id: int)
signal player_ship_registered(ship: Node)
signal player_ship_unregistered(ship: Node)

## 所有舰队
var fleets: Array = []
## 所有玩家飞船（弱引用）
var player_ships: Array = []

var _next_fleet_id: int = 1

## 所有敌对飞船的军团名称
const ENEMY_FACTION_NAME: String = "天蛇集团"
const PLAYER_FACTION_NAME: String = "玩家军团"

func _ready() -> void:
	print("FleetManager: 就绪")

## ==================== 玩家飞船管理 ====================

## 注册玩家飞船
func register_player_ship(ship: Node) -> void:
	if not ship:
		return
	# 检查是否已注册
	for ref in player_ships:
		if ref.get_ref() == ship:
			return
	player_ships.append(weakref(ship))
	player_ship_registered.emit(ship)
	print("FleetManager: 注册玩家飞船 ", ship.name)

## 注销玩家飞船
func unregister_player_ship(ship: Node) -> void:
	if not ship:
		return
	for i in range(player_ships.size() - 1, -1, -1):
		if player_ships[i].get_ref() == ship:
			player_ships.remove_at(i)
			break
	player_ship_unregistered.emit(ship)

## 获取所有有效玩家飞船
func get_all_player_ships() -> Array:
	var result: Array = []
	for ref in player_ships:
		var ship = ref.get_ref()
		if ship and is_instance_valid(ship):
			result.append(ship)
	return result

## 获取玩家飞船数量
func get_player_ship_count() -> int:
	return get_all_player_ships().size()

## ==================== 舰队管理 ====================

## 创建新舰队
func create_fleet(name: String):
	var fleet = FleetClass.new(name, _next_fleet_id)
	_next_fleet_id += 1
	fleets.append(fleet)
	fleet_created.emit(fleet.fleet_id)
	return fleet

## 删除舰队（飞船将变为无舰队状态）
func delete_fleet(fleet_id: int) -> bool:
	for i in range(fleets.size()):
		if fleets[i].fleet_id == fleet_id:
			var fleet = fleets[i]
			# 将所有飞船移出舰队
			for ref in fleet.ship_refs:
				var ship = ref.get_ref()
				if ship and is_instance_valid(ship) and ship.has_method("set_fleet"):
					ship.set_fleet(-1)
			fleets.remove_at(i)
			fleet_deleted.emit(fleet_id)
			return true
	return false

## 重命名舰队
func rename_fleet(fleet_id: int, new_name: String) -> bool:
	for fleet in fleets:
		if fleet.fleet_id == fleet_id:
			fleet.fleet_name = new_name
			fleet_renamed.emit(fleet_id, new_name)
			return true
	return false

## 将飞船加入舰队
func add_ship_to_fleet(ship: Node, fleet_id: int) -> bool:
	var fleet = get_fleet_by_id(fleet_id)
	if not fleet:
		return false
	if not ship:
		return false
	
	# 先从旧舰队移除
	remove_ship_from_fleet(ship)
	
	fleet.add_ship(ship)
	if ship.has_method("set_fleet"):
		ship.set_fleet(fleet_id)
	ship_added_to_fleet.emit(ship, fleet_id)
	return true

## 将飞船从舰队移除
func remove_ship_from_fleet(ship: Node) -> bool:
	if not ship:
		return false
	var removed = false
	for fleet in fleets:
		fleet.remove_ship(ship)
		removed = true
	if ship.has_method("set_fleet"):
		ship.set_fleet(-1)
	if removed:
		ship_removed_from_fleet.emit(ship, -1)
	return removed

## 根据 ID 获取舰队
func get_fleet_by_id(fleet_id: int):
	for fleet in fleets:
		if fleet.fleet_id == fleet_id:
			fleet.cleanup()
			return fleet
	return null

## 获取飞船所在的舰队
func get_fleet_of_ship(ship: Node):
	if not ship:
		return null
	for fleet in fleets:
		fleet.cleanup()
		for ref in fleet.ship_refs:
			var s = ref.get_ref() if ref is WeakRef else null
			if s == ship:
				return fleet
	return null

## 获取飞船所在舰队 ID
func get_fleet_id_of_ship(ship: Node) -> int:
	var fleet = get_fleet_of_ship(ship)
	return fleet.fleet_id if fleet else -1

## 获取所有未加入舰队的玩家飞船
func get_ships_without_fleet() -> Array:
	var all_ships = get_all_player_ships()
	var result: Array = []
	for ship in all_ships:
		var fleet = get_fleet_of_ship(ship)
		if not fleet:
			result.append(ship)
	return result

## 清理所有舰队中的无效引用
func cleanup_all() -> void:
	for fleet in fleets:
		fleet.cleanup()
	# 清理无效的玩家飞船引用
	player_ships = player_ships.filter(func(ref):
		var s = ref.get_ref()
		return s and is_instance_valid(s)
	)
