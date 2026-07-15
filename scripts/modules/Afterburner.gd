extends ShipModule
class_name Afterburner

## 加力推进器 - 提升飞船速度

var speed_boost: float = 0.0

func _apply_effect() -> void:
	if owner_ship:
		speed_boost = owner_ship.max_speed * 0.3  # 30%速度加成
		owner_ship.max_speed += speed_boost

func deactivate() -> void:
	super.deactivate()
	if owner_ship:
		owner_ship.max_speed -= speed_boost
		speed_boost = 0.0
