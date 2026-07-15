extends Resource
class_name WeaponData

## 武器数据定义

enum WeaponType { LASER, PROJECTILE, MISSILE, HYBRID }

@export var weapon_name: String = "小型激光炮"
@export var description: String = "基础激光武器"
@export var weapon_type: WeaponType = WeaponType.LASER
@export var damage_type: String = "热能"  # 热能/动能/爆炸
@export var damage: float = 25.0
@export var rate_of_fire: float = 2.0  # 每秒射击次数
@export var optimal_range: float = 1500.0  # 最佳射程
@export var falloff_range: float = 3000.0  # 失准范围
@export var tracking_speed: float = 0.1  # 跟踪速度
@export var signature_resolution: float = 40.0  # 信号分辨率
@export var capacitor_usage: float = 5.0  # 每次射击耗电
@export var powergrid_usage: float = 10.0
@export var cpu_usage: float = 10.0
@export var projectile_scene: PackedScene  # 弹体场景
@export var base_price: int = 10000
