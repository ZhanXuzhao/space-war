extends CharacterBody3D
class_name Ship

## 飞船基类 - 包含所有飞船共有的属性和行为

signal shield_changed(current: float, max_value: float)
signal armor_changed(current: float, max_value: float)
signal hull_changed(current: float, max_value: float)
signal capacitor_changed(current: float, max_value: float)
signal ship_destroyed()
signal target_locked(target: Ship)
signal target_lost(target: Ship)

## 飞船基础属性
@export var ship_data: ShipData
@export var max_shield: float = 800.0
@export var max_armor: float = 600.0
@export var max_hull: float = 800.0
@export var max_capacitor: float = 400.0
@export var capacitor_recharge: float = 20.0  # 每秒恢复量
@export var max_speed: float = 280.0
@export var cargo_capacity: float = 500.0
@export var signature_radius: float = 40.0
@export var max_locked_targets: int = 4

## 当前状态
var current_shield: float
var current_armor: float
var current_hull: float
var current_capacitor: float
var current_speed: float = 0.0
var is_alive: bool = true

## 移动控制（由 PlayerShip 或 AI 驱动）
var has_move_order: bool = false
var move_target: Vector3 = Vector3.ZERO

## 目标与战斗
var locked_targets: Array[Ship] = []
var active_target: Ship = null
var target_lock_progress: float = 0.0  # 0.0 ~ 1.0
var is_target_locking: bool = false
var current_targeting_range: float = 20000.0  # 锁定距离

## 模块与武器
var high_slot_modules: Array[Node] = []
var mid_slot_modules: Array[Node] = []
var low_slot_modules: Array[Node] = []
var weapon_nodes: Array[Node] = []

## 阵营
enum Faction { PLAYER, NPC_FRIENDLY, NPC_HOSTILE, NEUTRAL }
@export var faction: Faction = Faction.NEUTRAL

func _ready() -> void:
	_init_stats()

func _init_stats() -> void:
	current_shield = max_shield
	current_armor = max_armor
	current_hull = max_hull
	current_capacitor = max_capacitor

func _process(delta: float) -> void:
	if not is_alive:
		return
	_recharge_capacitor(delta)

func _recharge_capacitor(delta: float) -> void:
	if current_capacitor < max_capacitor:
		current_capacitor = minf(max_capacitor, current_capacitor + capacitor_recharge * delta)
		capacitor_changed.emit(current_capacitor, max_capacitor)

## 受到伤害
func take_damage(damage: float, _damage_type: String, _attacker: Node) -> void:
	if not is_alive:
		return
	
	var remaining = damage
	
	# 护盾吸收
	if current_shield > 0:
		var shield_damage = minf(current_shield, remaining)
		current_shield -= shield_damage
		remaining -= shield_damage
		shield_changed.emit(current_shield, max_shield)
	
	# 装甲吸收
	if remaining > 0 and current_armor > 0:
		var armor_damage = minf(current_armor, remaining)
		current_armor -= armor_damage
		remaining -= armor_damage
		armor_changed.emit(current_armor, max_armor)
	
	# 结构伤害
	if remaining > 0:
		current_hull -= remaining
		hull_changed.emit(current_hull, max_hull)
		if current_hull <= 0:
			_destroy()

func _destroy() -> void:
	is_alive = false
	ship_destroyed.emit()
	# 爆炸效果
	_spawn_explosion()
	queue_free()

func _spawn_explosion() -> void:
	# 简单的爆炸粒子效果 - 可通过场景扩展
	pass

## 锁定目标
func lock_target(target: Ship) -> bool:
	if not target.is_alive:
		return false
	if locked_targets.size() >= max_locked_targets:
		return false
	if target in locked_targets:
		return true
	
	var distance = global_position.distance_to(target.global_position)
	if distance > current_targeting_range:
		return false
	
	locked_targets.append(target)
	target_locked.emit(target)
	return true

func unlock_target(target: Ship) -> void:
	locked_targets.erase(target)
	if active_target == target:
		active_target = null
	target_lost.emit(target)

func set_active_target(target: Ship) -> void:
	if target in locked_targets:
		active_target = target

## 移动到目标位置（基类实现，PlayerShip 可覆写）
func order_move_to(position: Vector3) -> void:
	move_target = position
	has_move_order = true

## 使用电容
func use_capacitor(amount: float) -> bool:
	if current_capacitor >= amount:
		current_capacitor -= amount
		capacitor_changed.emit(current_capacitor, max_capacitor)
		return true
	return false

## 获取信息
func get_hull_percent() -> float:
	return current_hull / max_hull * 100.0

func get_armor_percent() -> float:
	return current_armor / max_armor * 100.0

func get_shield_percent() -> float:
	return current_shield / max_shield * 100.0

func get_capacitor_percent() -> float:
	return current_capacitor / max_capacitor * 100.0
