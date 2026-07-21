extends Node3D
class_name Projectile

## 弹体/导弹 - 从武器发射的投射物

@export var speed: float = 1000.0  # 飞行速度
@export var max_lifetime: float = 5.0  # 最长存在时间
@export var explosion_effect: PackedScene  # 爆炸特效

var target: Ship
var damage: float
var damage_type: String
var owner_ship: Ship
var scale_size: float = 1.0  # 弹体缩放（由发射时传入）
var lifetime: float = 0.0
var has_hit: bool = false

func _ready() -> void:
	# 应用缩放
	scale = Vector3.ONE * scale_size
	# 面向目标
	if target:
		look_at(target.global_position, Vector3.UP)

func _process(delta: float) -> void:
	if has_hit:
		return
	
	lifetime += delta
	if lifetime >= max_lifetime:
		queue_free()
		return
	
	if not target or not target.is_alive or not target.is_inside_tree():
		queue_free()
		return
	
	# 飞向目标
	var direction = (target.global_position - global_position).normalized()
	global_position += direction * speed * delta
	look_at(target.global_position, Vector3.UP)
	
	# 碰撞检测
	var distance = global_position.distance_to(target.global_position)
	if distance < 10.0:
		_hit_target()

func _hit_target() -> void:
	if has_hit:
		return
	has_hit = true
	
	if target and target.is_alive:
		var source = owner_ship if (owner_ship and is_instance_valid(owner_ship)) else null
		target.take_damage(damage, damage_type, source)
	
	# 爆炸效果
	_spawn_hit_explosion()
	
	queue_free()

func _spawn_hit_explosion() -> void:
	## 命中爆炸特效
	## 优先使用 explosion_effect（由 WeaponData 配置），否则使用默认 Explosion 场景
	# 检查全局设置：是否显示爆炸特效
	var g = get_node_or_null("/root/Global")
	if g and not g.explosion_visible:
		return
	var explosion_scene: PackedScene = null
	
	if explosion_effect:
		explosion_scene = explosion_effect
	else:
		# 默认爆炸
		explosion_scene = preload("res://scenes/effects/Explosion.tscn")
	
	if not explosion_scene:
		return
	
	var explosion = explosion_scene.instantiate()
	get_tree().root.add_child(explosion)
	explosion.global_position = global_position
	
	# 弹体爆炸统一为小尺寸
	if explosion is Explosion:
		explosion.size = Explosion.ExplosionSize.SMALL
		# 根据所有者阵营设置颜色
		if owner_ship and owner_ship is Ship:
			match owner_ship.faction:
				Ship.Faction.PLAYER:
					explosion.faction_color = Color(0.3, 0.7, 1.0)
				Ship.Faction.NPC_HOSTILE:
					explosion.faction_color = Color(1.0, 0.4, 0.05)
				_:
					explosion.faction_color = Color(1.0, 0.7, 0.2)
