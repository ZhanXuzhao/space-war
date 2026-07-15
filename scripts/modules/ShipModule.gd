extends Node
class_name ShipModule

## 飞船模块基类
## EVE风格的模块系统：护盾回充、装甲修复、推进器等

signal module_cycle_started()
signal module_cycle_finished()

@export var module_data: ModuleData
@export var auto_repeat: bool = true

var is_active: bool = false
var is_on_cooldown: bool = false
var cycle_timer: float = 0.0
var cooldown_timer: float = 0.0
var owner_ship: Ship

func _ready() -> void:
	owner_ship = get_parent() as Ship
	if not owner_ship:
		owner_ship = get_parent().get_parent() as Ship

func _process(delta: float) -> void:
	if is_on_cooldown:
		cooldown_timer -= delta
		if cooldown_timer <= 0:
			is_on_cooldown = false
	
	if is_active and cycle_timer > 0:
		cycle_timer -= delta
		if cycle_timer <= 0:
			_finish_cycle()
			if auto_repeat and is_active:
				_start_cycle()

## 激活模块
func activate() -> void:
	if is_active or is_on_cooldown:
		return
	is_active = true
	_start_cycle()

## 停用模块
func deactivate() -> void:
	is_active = false
	cycle_timer = 0.0

## 开始一个循环
func _start_cycle() -> void:
	if not owner_ship:
		return
	if not owner_ship.use_capacitor(module_data.capacitor_usage):
		is_active = false
		return
	
	cycle_timer = module_data.activation_time
	module_cycle_started.emit()

## 完成一个循环（应用效果）
func _finish_cycle() -> void:
	_apply_effect()
	module_cycle_finished.emit()
	
	# 进入冷却
	is_on_cooldown = true
	cooldown_timer = 0.5

## 应用模块效果 - 子类重写
func _apply_effect() -> void:
	pass
