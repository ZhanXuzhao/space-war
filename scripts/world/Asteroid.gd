extends RigidBody3D
class_name Asteroid

## 小行星 - 可开采的资源

signal asteroid_depleted(asteroid: Asteroid)

@export var ore_type: String = "三钛合金"  # 矿石类型
@export var ore_amount: float = 1000.0  # 总矿石量
@export var min_ore_amount: float = 200.0
@export var max_ore_amount: float = 3000.0
@export var respawn_time: float = 300.0  # 重生时间(秒)

var current_ore: float
var is_depleted: bool = false
var mining_difficulty: float = 1.0  # 开采难度

# 矿石价值字典 (每单位价值 ISK)
static var ore_values: Dictionary = {
	"三钛合金": 1,
	"同位素": 3,
	"克雷多": 8,
	"杰斯贝": 15,
	"双多特": 50,
	"超新星诺克石": 200
}

func _ready() -> void:
	current_ore = randf_range(min_ore_amount, max_ore_amount)
	# 随机旋转速度
	angular_velocity = Vector3(
		randf_range(-0.5, 0.5),
		randf_range(-0.5, 0.5),
		randf_range(-0.5, 0.5)
	)

## 开采
func mine(amount: float) -> float:
	if is_depleted:
		return 0.0
	
	var mined = minf(amount, current_ore)
	current_ore -= mined
	
	if current_ore <= 0:
		current_ore = 0
		is_depleted = true
		asteroid_depleted.emit(self)
		# 隐藏视觉，等待重生
		hide()
		await get_tree().create_timer(respawn_time).timeout
		_respawn()
	
	return mined

func _respawn() -> void:
	current_ore = randf_range(min_ore_amount, max_ore_amount)
	is_depleted = false
	show()

## 获取矿石价值
func get_ore_value() -> int:
	return ore_values.get(ore_type, 1)

## 获取当前矿石价值
func get_current_value() -> int:
	return int(current_ore) * get_ore_value()
