extends Node3D
class_name Explosion

## 太空爆炸特效
## 包含：核心火球、碎片飞溅、冲击波环、闪光
## 自动播放后自行销毁

enum ExplosionSize { SMALL, MEDIUM, LARGE, HUGE }

## 爆炸大小预设
@export var size: ExplosionSize = ExplosionSize.MEDIUM
## 自定义爆炸半径（覆盖预设）
@export var custom_radius: float = 0.0
## 阵营颜色（设置后将影响火光色调）
@export var faction_color: Color = Color(1.0, 0.6, 0.1)

var _duration: float = 2.0
var _timer: float = 0.0

# 子节点引用
var _fire_particles: GPUParticles3D
var _debris_particles: GPUParticles3D
var _shockwave: MeshInstance3D
var _flash_light: OmniLight3D
var _flash_mesh: MeshInstance3D

# 冲击波动画参数
var _shockwave_max_radius: float = 50.0
var _shockwave_grow_speed: float = 100.0

func _ready() -> void:
	_setup_explosion()
	_play()

func _setup_explosion() -> void:
	var radius = custom_radius if custom_radius > 0 else _get_radius_for_size()
	
	# ---- 1. 核心火球粒子 ----
	_fire_particles = GPUParticles3D.new()
	_fire_particles.name = "FireParticles"
	_fire_particles.emitting = false
	_fire_particles.one_shot = true
	_fire_particles.explosiveness = 1.0
	_fire_particles.randomness = 0.1
	_fire_particles.fixed_fps = 0
	_fire_particles.interpolate = false
	
	var fire_material = ParticleProcessMaterial.new()
	fire_material.particle_flag_align_y = false
	fire_material.direction = Vector3.UP
	fire_material.spread = 180.0
	fire_material.flatness = 0.0
	fire_material.gravity = Vector3.ZERO
	fire_material.initial_velocity_min = radius * 1.5
	fire_material.initial_velocity_max = radius * 3.0
	fire_material.scale_min = radius * 0.05
	fire_material.scale_max = radius * 0.2
	fire_material.scale_curve = _make_curve([
		Vector2(0.0, 1.0),
		Vector2(0.3, 1.5),
		Vector2(0.7, 1.2),
		Vector2(1.0, 0.3)
	])
	fire_material.color = Color(faction_color.r, faction_color.g, faction_color.b, 1.0)
	# 颜色随生命周期变化：中心白 -> 火光色 -> 暗红 -> 消散
	var color_ramp = Gradient.new()
	color_ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.4, 0.7, 1.0])
	color_ramp.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),           # 中心白炽
		Color(faction_color.r, faction_color.g, faction_color.b, 1.0),  # 火光色
		Color(1.0, 0.3, 0.05, 0.8),           # 橙红
		Color(0.6, 0.1, 0.02, 0.4),           # 暗红
		Color(0.0, 0.0, 0.0, 0.0)             # 消散
	])
	fire_material.color_ramp = color_ramp
	fire_material.angle_min = 0.0
	fire_material.angle_max = 360.0
	fire_material.angular_velocity_min = 0.0
	fire_material.angular_velocity_max = 6.0
	
	_fire_particles.process_material = fire_material
	_fire_particles.amount = int(radius * 1.5)
	_fire_particles.lifetime = _duration * 0.8
	_fire_particles.preprocess = 0.0
	_fire_particles.speed_scale = 1.0
	
	var fire_draw_pass = SphereMesh.new()
	fire_draw_pass.radius = 1.0
	fire_draw_pass.height = 2.0
	var fire_mat = StandardMaterial3D.new()
	fire_mat.albedo_color = Color.WHITE
	fire_mat.emission_enabled = true
	fire_mat.emission = Color(1.0, 0.8, 0.4)
	fire_mat.emission_energy_multiplier = 4.0
	fire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fire_draw_pass.material = fire_mat
	_fire_particles.draw_pass_1 = fire_draw_pass
	
	add_child(_fire_particles)
	
	# ---- 2. 碎片粒子（飞溅的金属碎块） ----
	_debris_particles = GPUParticles3D.new()
	_debris_particles.name = "DebrisParticles"
	_debris_particles.emitting = false
	_debris_particles.one_shot = true
	_debris_particles.explosiveness = 0.5
	_debris_particles.randomness = 0.2
	
	var debris_material = ParticleProcessMaterial.new()
	debris_material.direction = Vector3.UP
	debris_material.spread = 180.0
	debris_material.flatness = 0.0
	debris_material.gravity = Vector3.ZERO
	debris_material.initial_velocity_min = radius * 0.5
	debris_material.initial_velocity_max = radius * 2.0
	debris_material.scale_min = radius * 0.02
	debris_material.scale_max = radius * 0.08
	debris_material.scale_curve = _make_curve([
		Vector2(0.0, 1.0),
		Vector2(0.5, 0.8),
		Vector2(1.0, 0.3)
	])
	debris_material.angular_velocity_min = 0.0
	debris_material.angular_velocity_max = 20.0
	debris_material.angle_min = 0.0
	debris_material.angle_max = 360.0
	
	var debris_color_ramp = Gradient.new()
	debris_color_ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	debris_color_ramp.colors = PackedColorArray([
		Color(1.0, 0.8, 0.3, 1.0),
		Color(0.6, 0.4, 0.2, 1.0),
		Color(0.2, 0.2, 0.2, 0.0)
	])
	debris_material.color_ramp = debris_color_ramp
	
	_debris_particles.process_material = debris_material
	_debris_particles.amount = int(radius * 0.8)
	_debris_particles.lifetime = _duration * 1.2
	_debris_particles.preprocess = 0.0
	
	var debris_draw_pass = BoxMesh.new()
	debris_draw_pass.size = Vector3(1.0, 1.0, 1.0)
	var debris_mat = StandardMaterial3D.new()
	debris_mat.albedo_color = Color(0.5, 0.4, 0.3)
	debris_mat.metallic = 0.8
	debris_mat.roughness = 0.4
	debris_draw_pass.material = debris_mat
	_debris_particles.draw_pass_1 = debris_draw_pass
	
	add_child(_debris_particles)
	
	# ---- 3. 冲击波环（用 SurfaceTool 构建扁平圆环 Mesh，一直面向摄像机） ----
	_shockwave = MeshInstance3D.new()
	_shockwave.name = "Shockwave"
	
	var ring_mat = StandardMaterial3D.new()
	ring_mat.albedo_color = Color(faction_color.r, faction_color.g, faction_color.b, 0.6)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(faction_color.r * 0.8, faction_color.g * 0.5, faction_color.b * 0.2, 0.8)
	ring_mat.emission_energy_multiplier = 2.0
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	# 用 SurfaceTool 构建扁平圆环
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments = 32
	var inner_r = 0.5
	var outer_r = 2.0
	for i in range(segments):
		var a1 = 2.0 * PI * i / segments
		var a2 = 2.0 * PI * (i + 1) / segments
		var p1 = Vector3(cos(a1) * inner_r, 0.0, sin(a1) * inner_r)
		var p2 = Vector3(cos(a2) * inner_r, 0.0, sin(a2) * inner_r)
		var p3 = Vector3(cos(a1) * outer_r, 0.0, sin(a1) * outer_r)
		var p4 = Vector3(cos(a2) * outer_r, 0.0, sin(a2) * outer_r)
		# 两个三角形组成一个四边形 ring segment
		st.add_vertex(p1)
		st.add_vertex(p2)
		st.add_vertex(p3)
		st.add_vertex(p2)
		st.add_vertex(p4)
		st.add_vertex(p3)
	var ring_mesh = st.commit()
	ring_mesh.surface_set_material(0, ring_mat)
	
	_shockwave.mesh = ring_mesh
	_shockwave.visible = false
	add_child(_shockwave)
	
	# ---- 4. 闪光 ----
	_flash_mesh = MeshInstance3D.new()
	_flash_mesh.name = "FlashMesh"
	var flash_sphere = SphereMesh.new()
	flash_sphere.radius = 1.0
	flash_sphere.height = 2.0
	var flash_mat = StandardMaterial3D.new()
	flash_mat.albedo_color = Color.WHITE
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1.0, 0.9, 0.6)
	flash_mat.emission_energy_multiplier = 8.0
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_sphere.material = flash_mat
	_flash_mesh.mesh = flash_sphere
	_flash_mesh.scale = Vector3(radius * 0.3, radius * 0.3, radius * 0.3)
	add_child(_flash_mesh)
	
	_flash_light = OmniLight3D.new()
	_flash_light.name = "FlashLight"
	_flash_light.omni_range = radius * 8.0
	_flash_light.light_color = Color(faction_color.r * 0.8 + 0.2, faction_color.g * 0.5 + 0.5, faction_color.b * 0.3 + 0.3)
	_flash_light.light_energy = 5.0
	_flash_light.light_indirect_energy = 2.0
	add_child(_flash_light)

func _play() -> void:
	# 启动粒子
	_fire_particles.emitting = true
	_debris_particles.emitting = true
	
	# 冲击波初始可见
	_shockwave.visible = true
	_shockwave.scale = Vector3(0.1, 0.1, 0.1)
	
	_shockwave_max_radius = _get_radius_for_size() * 2.0
	_shockwave_grow_speed = _shockwave_max_radius / 0.8  # 0.8秒扩张到最大
	
	_timer = 0.0

func _process(delta: float) -> void:
	_timer += delta
	
	# 冲击波扩张
	if _shockwave and _shockwave.visible:
		var progress = _timer / 0.8
		if progress < 1.0:
			var scale_val = 0.1 + progress * 9.9  # 0.1 -> 10.0
			_shockwave.scale = Vector3(scale_val, scale_val, scale_val)
			# 透明度随扩张递减
			var mat = _shockwave.mesh.surface_get_material(0)
			if mat:
				mat.albedo_color.a = 0.6 * (1.0 - progress)
				mat.emission_energy_multiplier = 2.0 * (1.0 - progress)
		else:
			_shockwave.visible = false
	
	# 闪光衰减
	if _flash_mesh:
		var flash_progress = _timer / 0.3
		if flash_progress < 1.0:
			_flash_mesh.scale = Vector3(1.0, 1.0, 1.0) * _get_radius_for_size() * 0.3 * (1.0 + flash_progress * 2.0)
			var alpha = 1.0 - flash_progress
			var mat = _flash_mesh.mesh.surface_get_material(0)
			if mat:
				mat.albedo_color.a = alpha
				mat.emission_energy_multiplier = 8.0 * (1.0 - flash_progress * 0.8)
		else:
			_flash_mesh.visible = false
	
	# 灯光衰减
	if _flash_light:
		var light_progress = _timer / 0.5
		if light_progress < 1.0:
			_flash_light.light_energy = 5.0 * (1.0 - light_progress * 0.9)
		else:
			_flash_light.light_energy = 0.0
	
	# 自动销毁
	if _timer >= _duration * 1.5:
		queue_free()

## 创建浮点曲线辅助
func _make_curve(points: Array) -> Curve:
	var curve = Curve.new()
	curve.min_value = 0.0
	curve.max_value = 2.0
	for i in points.size():
		var p = points[i] as Vector2
		curve.add_point(Vector2(p.x, p.y))
		if i > 0 and i < points.size() - 1:
			curve.set_point_left_tangent(i, 0.0)
			curve.set_point_right_tangent(i, 0.0)
	return curve

func _get_radius_for_size() -> float:
	match size:
		ExplosionSize.SMALL:
			return 20.0   # 小行星、导弹
		ExplosionSize.MEDIUM:
			return 50.0   # 护卫舰
		ExplosionSize.LARGE:
			return 100.0  # 巡洋舰
		ExplosionSize.HUGE:
			return 200.0  # 战列舰
	return 50.0
