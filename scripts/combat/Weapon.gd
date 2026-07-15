extends Node3D
class_name Weapon

## 武器系统 - 安装在飞船上的武器

signal weapon_fired(weapon: Weapon)
@export var weapon_data: WeaponData
@export var muzzle_node_path: NodePath  # 炮口位置

var is_active: bool = false
var is_on_cooldown: bool = false
var cooldown_timer: float = 0.0
var owner_ship: Ship
var owner_targeting_range: float = 0.0

func _ready() -> void:
	owner_ship = get_parent() as Ship
	if owner_ship:
		owner_targeting_range = owner_ship.current_targeting_range
	cooldown_timer = 1.0 / weapon_data.rate_of_fire if weapon_data.rate_of_fire > 0 else 0.5

func _process(delta: float) -> void:
	if is_on_cooldown:
		cooldown_timer -= delta
		if cooldown_timer <= 0:
			is_on_cooldown = false

## 激活/停用武器
func activate() -> void:
	is_active = true

func deactivate() -> void:
	is_active = false

## 尝试射击当前目标
func try_fire(target: Ship, _delta: float) -> bool:
	if not is_active or is_on_cooldown:
		return false
	if not target or not target.is_alive:
		return false
	if not owner_ship:
		return false
	
	# 检查距离
	var distance = owner_ship.global_position.distance_to(target.global_position)
	if distance > owner_targeting_range:
		return false
	
	# 检查电容
	if not owner_ship.use_capacitor(weapon_data.capacitor_usage):
		return false
	
	# 命中判定 (简化的跟踪公式)
	var hit_chance = _calculate_hit_chance(target, distance)
	if randf() <= hit_chance:
		_fire_projectile(target)
	
	# 进入冷却
	is_on_cooldown = true
	cooldown_timer = 1.0 / weapon_data.rate_of_fire
	weapon_fired.emit(self)
	return true

## 计算命中率
func _calculate_hit_chance(target: Ship, distance: float) -> float:
	# 基于距离、跟踪速度、目标信号半径的简化公式
	var optimal = weapon_data.optimal_range
	var falloff = weapon_data.falloff_range
	
	# 距离衰减
	var range_chance = 1.0
	if distance > optimal:
		range_chance = maxf(0.0, 1.0 - (distance - optimal) / falloff)
	
	# 跟踪速度与目标信号半径
	var tracking_factor = weapon_data.tracking_speed * target.signature_radius / 40.0
	tracking_factor = clampf(tracking_factor, 0.1, 1.0)
	
	return clampf(range_chance * tracking_factor, 0.0, 1.0)

## 发射弹体
func _fire_projectile(target: Ship) -> void:
	if not weapon_data.projectile_scene or not is_inside_tree():
		# 无弹体场景时直接造成伤害
		_direct_damage(target)
		return
	
	var muzzle = get_node_or_null(muzzle_node_path) if muzzle_node_path else self
	var projectile = weapon_data.projectile_scene.instantiate() as Projectile
	if projectile:
		get_tree().root.add_child(projectile)
		projectile.global_position = muzzle.global_position
		projectile.target = target
		projectile.damage = weapon_data.damage
		projectile.damage_type = weapon_data.damage_type
		projectile.owner_ship = owner_ship

## 直接造成伤害（无弹体时）
func _direct_damage(target: Ship) -> void:
	target.take_damage(weapon_data.damage, weapon_data.damage_type, owner_ship)
