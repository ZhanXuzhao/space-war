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

## 炮台安装平面的法线方向（飞船局部坐标系），默认朝前
## 炮台默认朝向沿此方向向外，且与法线夹角 ≤ 90°
@export var mount_local_normal: Vector3 = Vector3(0, 0, -1)

# 武器发射台建模
var weapon_mount: MeshInstance3D
const MOUNT_LENGTH: float = 30.0
const MOUNT_RADIUS: float = 8.0

# 激光特效
var laser_beam: MeshInstance3D
var laser_beam_timer: float = 0.0
var laser_end_pos: Vector3 = Vector3.ZERO
var laser_track_target: Ship = null  # 命中时追踪目标移动
const LASER_DURATION: float = 1.0
const LASER_THICKNESS: float = 4.5
const MISS_OFFSET_RANGE: float = 120.0  # 未命中时激光偏移范围

## 根据武器类型返回炮台颜色
func _get_mount_color() -> Color:
	match weapon_data.weapon_type:
		WeaponData.WeaponType.LASER:
			return Color(1.0, 0.2, 0.1)    # 红色 — 热能激光
		WeaponData.WeaponType.MISSILE:
			return Color(0.8, 0.6, 0.1)    # 金色 — 爆炸导弹
		WeaponData.WeaponType.PROJECTILE:
			return Color(0.3, 0.5, 0.9)    # 蓝色 — 动能弹
		WeaponData.WeaponType.HYBRID:
			return Color(0.6, 0.3, 0.9)    # 紫色 — 混合武器
		_:
			return Color(0.4, 0.4, 0.45)   # 默认灰色

func _ready() -> void:
	owner_ship = get_parent() as Ship
	if owner_ship:
		owner_targeting_range = owner_ship.current_targeting_range
	# 攻击间隔3秒
	cooldown_timer = 3.0
	
	# 创建武器发射台圆柱模型
	weapon_mount = MeshInstance3D.new()
	weapon_mount.name = "WeaponMount"
	var mount_mesh = CylinderMesh.new()
	mount_mesh.top_radius = MOUNT_RADIUS
	mount_mesh.bottom_radius = MOUNT_RADIUS
	mount_mesh.height = MOUNT_LENGTH
	var mount_mat = StandardMaterial3D.new()
	mount_mat.albedo_color = _get_mount_color()
	mount_mat.metallic = 0.7
	mount_mat.roughness = 0.3
	mount_mesh.material = mount_mat
	weapon_mount.mesh = mount_mesh
	# 圆柱体默认沿Y轴，旋转使其沿-Z方向（飞船前进方向）
	weapon_mount.rotate_x(deg_to_rad(90.0))
	# 向前平移一半长度，使发射台从基点向前延伸
	weapon_mount.position.z = -MOUNT_LENGTH / 2.0
	add_child(weapon_mount)
	
	# 创建激光光束 MeshInstance3D
	laser_beam = MeshInstance3D.new()
	laser_beam.name = "LaserBeam"
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = LASER_THICKNESS
	cylinder.bottom_radius = LASER_THICKNESS
	cylinder.height = 1.0
	var mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/laser_beam.gdshader")
	mat.set_shader_parameter("center_color", Color(1.0, 0.6, 0.0))
	mat.set_shader_parameter("edge_color", Color(1.0, 0.1, 0.05))
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
	
	# 武器发射台对准目标方向
	_rotate_toward_target(delta)

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

## 武器发射台朝向目标旋转（平滑跟踪），带角度限制
func _rotate_toward_target(delta: float) -> void:
	var target: Ship = assigned_target if assigned_target and assigned_target.is_alive else null
	
	if target:
		# 将目标方向转换到武器局部坐标系（相对于父节点飞船）
		var parent = get_parent()
		if not parent:
			return
		var target_dir_global = (target.global_position - global_position).normalized()
		var parent_basis = parent.global_basis
		var local_dir = parent_basis.inverse() * target_dir_global
		
		# 限制旋转角度：与安装平面法线夹角 ≤ 90°
		local_dir = _clamp_to_mount_cone(local_dir)
		
		var target_quat = Quaternion(Basis.looking_at(local_dir, Vector3.UP))
		quaternion = quaternion.slerp(target_quat, 3.0 * delta)
	else:
		# 无目标时回到安装平面法线方向（垂直平面向外）
		var rest_quat = Quaternion(Basis.looking_at(mount_local_normal, Vector3.UP))
		quaternion = quaternion.slerp(rest_quat, 1.0 * delta)

## 限制炮台局部方向：与安装平面法线的夹角 ≤ 90°（不能转到平面反面）
func _clamp_to_mount_cone(local_dir: Vector3) -> Vector3:
	var normal := mount_local_normal.normalized()
	var max_angle := deg_to_rad(90.0)
	
	var angle := normal.angle_to(local_dir)
	if angle <= max_angle:
		return local_dir  # 在半球范围内
	
	# 超出范围：将方向投影到圆锥表面
	var axis := normal.cross(local_dir).normalized()
	if axis.length_squared() < 0.001:
		axis = Vector3.UP
	return normal.rotated(axis, max_angle)

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
	
	# 检查目标是否在炮台转向范围内
	var parent = get_parent()
	if parent:
		var target_dir_global = (target.global_position - global_position).normalized()
		var parent_basis = parent.global_basis
		var local_dir = parent_basis.inverse() * target_dir_global
		var angle_deg = rad_to_deg(mount_local_normal.normalized().angle_to(local_dir))
		if angle_deg > 90.0:
			return false
	
	# 检查电容
	if not owner_ship.use_capacitor(weapon_data.capacitor_usage):
		return false
	
	# 命中判定 (简化的跟踪公式)
	var hit_chance = _calculate_hit_chance(target, distance)
	var is_hit = randf() <= hit_chance
	
	if is_hit:
		_fire_projectile(target)
		# 命中：激光追踪目标（仅对非导弹武器显示激光特效）
		if weapon_data.weapon_type != WeaponData.WeaponType.MISSILE:
			_show_laser_hit(target)
	else:
		# 未命中（仅对非导弹武器显示激光特效）
		if weapon_data.weapon_type != WeaponData.WeaponType.MISSILE:
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

## 获取炮台末端中点（发射点）的全局坐标
func _get_muzzle_global_position() -> Vector3:
	if muzzle_node_path:
		var muzzle_node = get_node_or_null(muzzle_node_path)
		if muzzle_node:
			return muzzle_node.global_position
	if weapon_mount:
		# 炮台圆柱末端中点 = 炮台中心沿朝前方向偏移半个长度
		return weapon_mount.global_position + (-weapon_mount.global_basis.z * MOUNT_LENGTH / 2.0)
	return global_position

## 更新激光光束位置（每帧刷新起点 = 炮口实时位置）
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
	else:
		# 未命中：起点随炮口实时刷新，终点保持固定偏移
		_render_laser_beam()

## 渲染激光光束（从炮口到 end_pos）
func _render_laser_beam() -> void:
	var start_pos = _get_muzzle_global_position()
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
	
	# 距离衰减（导弹追踪目标，不受失准范围影响）
	var range_chance = 1.0
	if weapon_data.weapon_type != WeaponData.WeaponType.MISSILE:
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
	
	# 从炮台末端中点发射
	var muzzle_pos = _get_muzzle_global_position()
	
	var projectile = weapon_data.projectile_scene.instantiate() as Projectile
	if projectile:
		get_tree().root.add_child(projectile)
		projectile.global_position = muzzle_pos
		projectile.target = target
		projectile.damage = weapon_data.damage
		projectile.damage_type = weapon_data.damage_type
		projectile.owner_ship = owner_ship
		projectile.scale_size = weapon_data.projectile_scale
		projectile.speed = weapon_data.projectile_speed
		
		# 根据武器射程计算弹体飞行寿命，确保能飞到目标
		# 有效射程 = optimal_range + falloff_range
		var flight_range = weapon_data.optimal_range + weapon_data.falloff_range
		projectile.max_lifetime = flight_range / projectile.speed

## 直接造成伤害（无弹体时）
func _direct_damage(target: Ship) -> void:
	target.take_damage(weapon_data.damage, weapon_data.damage_type, owner_ship)
