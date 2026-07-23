extends RefCounted
class_name Fleet

## 舰队数据类 - 存储舰队信息

var fleet_id: int
var fleet_name: String
var ship_refs: Array = []  # 弱引用存储飞船

func _init(name: String, id: int) -> void:
	fleet_name = name
	fleet_id = id

## 获取舰队中所有有效飞船
func get_valid_ships() -> Array:
	var result: Array = []
	for ref in ship_refs:
		var ship = ref.get_ref() if ref is WeakRef else null
		if ship and is_instance_valid(ship):
			result.append(ship)
	return result

## 添加飞船到舰队
func add_ship(ship: Node) -> void:
	if not ship:
		return
	for ref in ship_refs:
		var s = ref.get_ref() if ref is WeakRef else null
		if s == ship:
			return
	ship_refs.append(weakref(ship))

## 从舰队移除飞船
func remove_ship(ship: Node) -> void:
	if not ship:
		return
	for i in range(ship_refs.size() - 1, -1, -1):
		var ref_entry = ship_refs[i]
		var s = ref_entry.get_ref() if ref_entry is WeakRef else null
		if s == ship or not is_instance_valid(s):
			ship_refs.remove_at(i)

## 清理无效引用
func cleanup() -> void:
	ship_refs = ship_refs.filter(func(ref):
		var s = ref.get_ref() if ref is WeakRef else null
		return s and is_instance_valid(s)
	)

## 舰队中飞船数量
func ship_count() -> int:
	cleanup()
	return ship_refs.size()
