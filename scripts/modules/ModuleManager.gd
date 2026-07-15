extends Node
class_name ModuleManager

## 模块管理器 - 管理飞船所有已安装模块

signal module_activated(module_ref: Node)
signal module_deactivated(module_ref: Node)

var parent_ship: Ship
var high_slots: Array[Node] = []
var mid_slots: Array[Node] = []
var low_slots: Array[Node] = []

func _ready() -> void:
	parent_ship = get_parent() as Ship

## 安装模块
func install_module(module: Node, slot_type: String, slot_index: int) -> bool:
	match slot_type:
		"high":
			while high_slots.size() <= slot_index:
				high_slots.append(null)
			high_slots[slot_index] = module
		"mid":
			while mid_slots.size() <= slot_index:
				mid_slots.append(null)
			mid_slots[slot_index] = module
		"low":
			while low_slots.size() <= slot_index:
				low_slots.append(null)
			low_slots[slot_index] = module
		_:
			return false
	
	add_child(module)
	return true

## 激活模块
func activate_module(slot_index: int, slot_type: String) -> void:
	var module = _get_module(slot_index, slot_type)
	if module and module.has_method("activate"):
		module.activate()
		module_activated.emit(module)

## 停用模块
func deactivate_module(slot_index: int, slot_type: String) -> void:
	var module = _get_module(slot_index, slot_type)
	if module and module.has_method("deactivate"):
		module.deactivate()
		module_deactivated.emit(module)

func _get_module(slot_index: int, slot_type: String):
	match slot_type:
		"high":
			return high_slots[slot_index] if slot_index < high_slots.size() else null
		"mid":
			return mid_slots[slot_index] if slot_index < mid_slots.size() else null
		"low":
			return low_slots[slot_index] if slot_index < low_slots.size() else null
	return null
