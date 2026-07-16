extends Node3D
class_name Weapon

## 武器系统 - 安装在飞船上的武器

signal weapon_fired(weapon: Weapon)
signal target_changed(weapon: Weapon, target: Ship)

@export var weapon_data: WeaponData
@export var muzzle_node_path: NodePath  # 炮口位置

var is_active: bool = false
var is_on_cooldown: bool = false
var cooldown_timer: float = 0.0
var owner_ship: Ship
var owner_targeting_range: float = 0.0

## 独立目标分配 — 每个武器可攻击不同目标
var assigned_target: Ship = null

# 激光特效
var laser_beam: MeshInstance3D
var laser_beam_timer: float = 0.0
var laser_end_pos: Vector3 = Vector3.ZERO
var laser_track_target: Ship = null  # 命中时追踪目标移动
const LASER_DURATION: float = 1.0
const LASER_THICKNESS: float = 1.5
const MISS_OFFSET_RANGE: float = 120.0  # 未命中时激光偏移范围

func _ready() -> void:
	owner_ship = get_parent() as Ship
	if owner_ship:
		owner_targeting_range = owner_ship.current_targeting_range
	# 攻击间隔3秒
	cooldown_timer = 3.0
	
	# 创建激光光束 MeshInstance3D
	laser_beam = MeshInstance3D.new()
	laser_beam.name = "LaserBeam"
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = LASER_THICKNESS
	cylinder.bottom_radius = LASER_THICKNESS
	cylinder.height = 1.0
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.2, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.2, 0.1)
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cylinder.material = mat
	laser_beam.mesh = cylinder
	laser_beam.visible = false
	laser_beam.top_level = true
	add_child(laser_beam)

func _process(delta: float) -> void:
	# 冷却计时
	if is_on_cooldown:
		cooldown_timer -= delta
		if cooldown_timer <= 0:
			is_on_cooldown = false
	
	# 自动攻击已分配的目标
	if assigned_target and is_instance_valid(assigned_target) and assigned_target.is_alive:
		try_fire(assigned_target, delta)
	elif assigned_target:
		# 目标已失效，清除分配
		_clear_assigned_target()
	
	# 激光光束持续更新（持续1秒后消失）
	if laser_beam_timer > 0:
		laser_beam_timer -= delta
		if laser_beam_timer <= 0:
			laser_beam.visible = false
			laser_track_target = null
		else:
			_update_laser_beam_position()

## 激活/停用武器
func activate() -> void:
	is_active = true

func deactivate() -> void:
	is_active = false

## 分配武器攻击目标（不同武器可攻击不同目标）
func assign_target(target: Ship) -> void:
	if target and is_instance_valid(target) and target.is_alive:
		assigned_target = target
		is_active = true
		target_changed.emit(self, target)

## 清除武器目标分配
func clear_target() -> void:
	_clear_assigned_target()

func _clear_assigned_target() -> void:
	assigned_target = null
	target_changed.emit(self, null)

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
	var is_hit = randf() <= hit_chance
	
	if is_hit:
		_fire_projectile(target)
		# 命中：激光追踪目标
		_show_laser_hit(target)
	else:
		# 未命中：激光打到目标身旁随机偏移位置
		_show_laser_miss(target)
	
	# 输出攻击日志
	_log_attack(target, is_hit)
	
	# 进入冷却（3秒攻击间隔）
	is_on_cooldown = true
	cooldown_timer = 3.0
	weapon_fired.emit(self)
	return true

## 命中时显示激光（追踪目标当前位置）
func _show_laser_hit(target: Ship) -> void:
	laser_track_target = target
	laser_end_pos = target.global_position
	laser_beam_timer = LASER_DURATION
	_render_laser_beam()
	laser_beam.visible = true

## 未命中时显示激光（打到目标身旁随机偏移位置）
func _show_laser_miss(target: Ship) -> void:
	laser_track_target = null
	# 在目标周围随机偏移
	var offset = Vector3(
		randf_range(-MISS_OFFSET_RANGE, MISS_OFFSET_RANGE),
		randf_range(-MISS_OFFSET_RANGE * 0.5, MISS_OFFSET_RANGE * 0.5),
		randf_range(-MISS_OFFSET_RANGE, MISS_OFFSET_RANGE)
	)
	laser_end_pos = target.global_position + offset
	laser_beam_timer = LASER_DURATION
	_render_laser_beam()
	laser_beam.visible = true

## 更新激光光束位置
func _update_laser_beam_position() -> void:
	if laser_track_target and laser_track_target.is_alive:
		# 命中：持续追踪目标当前位置
		laser_end_pos = laser_track_target.global_position
		_render_laser_beam()
	elif laser_track_target and not laser_track_target.is_alive:
		# 目标被摧毁，激光消失
		laser_beam.visible = false
		laser_beam_timer = 0.0
		laser_track_target = null
	# 未命中：保持固定偏移位置不变

## 渲染激光光束（从炮口到 end_pos）
func _render_laser_beam() -> void:
	var muzzle = get_node_or_null(muzzle_node_path) if muzzle_node_path else self
	var start_pos = muzzle.global_position
	var end_pos = laser_end_pos
	var mid_point = (start_pos + end_pos) / 2.0
	var distance = start_pos.distance_to(end_pos)
	
	if distance < 1.0:
		laser_beam.visible = false
		return
	
	# 构建旋转基，使 Y 轴指向目标方向（CylinderMesh 沿 Y 轴）
	var dir = (end_pos - start_pos).normalized()
	var up_ref = Vector3.UP if abs(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var right = dir.cross(up_ref).normalized()
	var up = right.cross(dir).normalized()
	
	laser_beam.global_position = mid_point
	laser_beam.global_basis = Basis(right, dir, up)
	laser_beam.scale = Vector3(1.0, distance, 1.0)

## 输出攻击日志（到控制台和UI消息栏）
func _log_attack(target: Ship, is_hit: bool) -> void:
	var attacker_name = owner_ship.ship_data.ship_name if owner_ship.ship_data else "未知"
	var target_name = target.ship_data.ship_name if target.ship_data else "未知"
	var weapon_name = weapon_data.weapon_name if weapon_data else "未知武器"
	var faction_str = "玩家" if owner_ship.faction == owner_ship.Faction.PLAYER else "敌对"
	
	var global_ref = get_node_or_null("/root/Global")
	
	if is_hit:
		var msg = "[%s] %s 用「%s」攻击 %s — 命中！造成 %.1f 点%s伤害" % [
			faction_str, attacker_name, weapon_name, target_name,
			weapon_data.damage, weapon_data.damage_type
		]
		if global_ref and global_ref.has_signal("combat_log"):
			global_ref.combat_log.emit(msg, Color(1.0, 0.3, 0.1))
	else:
		var msg = "[%s] %s 用「%s」攻击 %s — Miss！" % [
			faction_str, attacker_name, weapon_name, target_name
		]
		if global_ref and global_ref.has_signal("combat_log"):
			global_ref.combat_log.emit(msg, Color(0.6, 0.6, 0.6))

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
