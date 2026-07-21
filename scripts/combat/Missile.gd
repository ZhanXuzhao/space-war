extends Projectile
class_name Missile

## 导弹弹体
## 使用场景中的 .glb 模型 + 程序生成的尾焰和灯光
## 支持大(50m)/中(10m)/小(5m)三种尺寸

## 导弹尺寸枚举（值 = 目标长度，米）
## 太空战场距离远，小号至少 20m 才看得见
enum MissileSize {
	SMALL = 20,
	MEDIUM = 40,
	LARGE = 120,
}

## 导弹尺寸（决定最终缩放）
@export var missile_size: MissileSize = MissileSize.MEDIUM
## .glb 模型的原始长度（米），用于计算缩放系数
@export var model_base_length: float = 10.0

# 导弹子节点
var _model_node: Node3D         # 场景中的 .glb 模型
var _tail_flame: GPUParticles3D
var _missile_light: OmniLight3D

# 清理状态
var _cleaning_up: bool = false

func _ready() -> void:
	# 查找场景中的 .glb 模型节点（Missile.tscn 里的子节点）
	_model_node = get_child(0) if get_child_count() > 0 else null
	
	# 根据武器传入的 scale_size 自动选择导弹尺寸
	# FRIGATE: proj_scale=0.6 → SMALL(20m)
	# CRUISER: proj_scale=1.0 → MEDIUM(40m)
	# BATTLESHIP: proj_scale=1.8 → LARGE(120m)
	if scale_size <= 0.7:
		missile_size = MissileSize.SMALL
	elif scale_size >= 1.5:
		missile_size = MissileSize.LARGE
	else:
		missile_size = MissileSize.MEDIUM
	
	# 创建尾焰和灯光（使用 .glb 模型，代码只生成特效）
	_setup_effects()
	
	# 计算最终缩放 = 目标长度 / 模型原始长度
	var target_length = missile_size
	var scale_factor = target_length / model_base_length
	scale = Vector3.ONE * scale_factor
	
	# 面向目标
	if target:
		look_at(target.global_position, Vector3.UP)

## 创建尾焰和灯光特效（依赖导弹最终尺寸）
func _setup_effects() -> void:
	var target_length = missile_size
	
	# 检查全局设置：是否显示尾焰
	var g = get_node_or_null("/root/Global")
	var show_trail = true
	if g:
		show_trail = g.missile_trail_visible
	
	if not show_trail:
		# 不显示尾焰，但保留灯光
		_missile_light = OmniLight3D.new()
		_missile_light.name = "MissileLight"
		_missile_light.omni_range = target_length * 3.0
		_missile_light.light_color = Color(1.0, 0.6, 0.1)
		_missile_light.light_energy = 1.5
		_missile_light.position.z = target_length * 0.2
		add_child(_missile_light)
		return
	
	# ---- 1. 尾焰粒子 ----
	_tail_flame = GPUParticles3D.new()
	_tail_flame.name = "TailFlame"
	_tail_flame.emitting = true
	_tail_flame.one_shot = false
	_tail_flame.explosiveness = 0.0
	_tail_flame.randomness = 0.3
	_tail_flame.fixed_fps = 0
	_tail_flame.interpolate = false
	# 尾焰位置根据导弹尺寸偏移到尾部
	_tail_flame.position.z = target_length * 0.4
	
	var flame_material = ParticleProcessMaterial.new()
	flame_material.direction = Vector3(0, 0, 1)  # 向后喷出（+Z方向）
	flame_material.spread = 30.0
	flame_material.flatness = 0.0
	flame_material.gravity = Vector3.ZERO
	flame_material.initial_velocity_min = target_length * 1.0
	flame_material.initial_velocity_max = target_length * 2.5
	flame_material.scale_min = target_length * 0.03
	flame_material.scale_max = target_length * 0.08
	flame_material.scale_curve = _make_flame_curve()
	
	var flame_color_ramp = Gradient.new()
	flame_color_ramp.offsets = PackedFloat32Array([0.0, 0.3, 0.6, 1.0])
	flame_color_ramp.colors = PackedColorArray([
		Color(1.0, 1.0, 0.8, 1.0),   # 白炽
		Color(1.0, 0.7, 0.1, 0.9),   # 橙黄
		Color(1.0, 0.3, 0.05, 0.5),  # 橙红
		Color(0.5, 0.1, 0.0, 0.0)    # 消散
	])
	flame_material.color_ramp = flame_color_ramp
	
	_tail_flame.process_material = flame_material
	_tail_flame.amount = int(target_length * 2)
	_tail_flame.lifetime = 0.4
	_tail_flame.preprocess = 0.0
	_tail_flame.speed_scale = 1.0
	
	var flame_draw = SphereMesh.new()
	flame_draw.radius = 0.5
	flame_draw.height = 1.0
	var flame_mat = StandardMaterial3D.new()
	flame_mat.albedo_color = Color.WHITE
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(1.0, 0.8, 0.3)
	flame_mat.emission_energy_multiplier = 3.0
	flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_draw.material = flame_mat
	_tail_flame.draw_pass_1 = flame_draw
	
	add_child(_tail_flame)
	
	# ---- 2. 导弹发光 ----
	_missile_light = OmniLight3D.new()
	_missile_light.name = "MissileLight"
	_missile_light.omni_range = target_length * 3.0
	_missile_light.light_color = Color(1.0, 0.6, 0.1)
	_missile_light.light_energy = 1.5
	_missile_light.position.z = target_length * 0.2
	add_child(_missile_light)

## 尾焰粒子大小曲线
func _make_flame_curve() -> Curve:
	var curve = Curve.new()
	curve.min_value = 0.0
	curve.max_value = 2.0
	curve.add_point(Vector2(0.0, 0.3))
	curve.add_point(Vector2(0.2, 1.0))
	curve.add_point(Vector2(0.6, 0.8))
	curve.add_point(Vector2(1.0, 0.0))
	return curve

## 停止尾焰并延迟销毁（让尾焰粒子自然消散）
func _stop_and_free() -> void:
	if _cleaning_up:
		return
	_cleaning_up = true
	
	if _tail_flame:
		_tail_flame.emitting = false
		_tail_flame.one_shot = true
	
	# 等尾焰粒子生命周期结束后再销毁（若无尾焰则直接销毁）
	if _tail_flame:
		await get_tree().create_timer(0.5).timeout
	else:
		await get_tree().process_frame
	queue_free()

func _process(delta: float) -> void:
	if has_hit or _cleaning_up:
		return
	
	lifetime += delta
	if lifetime >= max_lifetime:
		_stop_and_free()
		return
	
	if not target or not target.is_alive or not target.is_inside_tree():
		_stop_and_free()
		return
	
	# 飞向目标
	var direction = (target.global_position - global_position).normalized()
	global_position += direction * speed * delta
	look_at(target.global_position, Vector3.UP)
	
	# 碰撞检测
	var distance = global_position.distance_to(target.global_position)
	if distance < 10.0:
		_hit_target()
