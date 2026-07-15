extends Node3D
class_name Projectile

## 弹体/导弹 - 从武器发射的投射物

@export var speed: float = 500.0  # 飞行速度
@export var max_lifetime: float = 5.0  # 最长存在时间
@export var explosion_effect: PackedScene  # 爆炸特效

var target: Ship
var damage: float
var damage_type: String
var owner_ship: Ship
var lifetime: float = 0.0
var has_hit: bool = false

func _ready() -> void:
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
		target.take_damage(damage, damage_type, owner_ship)
	
	# 爆炸效果
	if explosion_effect:
		var explosion = explosion_effect.instantiate()
		get_tree().root.add_child(explosion)
		explosion.global_position = global_position
	
	queue_free()
