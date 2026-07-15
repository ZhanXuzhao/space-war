extends Resource
class_name ShipData

## 飞船数据定义 - 资源类

@export var ship_name: String = "秃鹫级"
@export var description: String = "新手推荐的基础护卫舰"
@export_group("属性")
@export var hull_hp: float = 800.0
@export var armor_hp: float = 600.0
@export var shield_hp: float = 800.0
@export var capacitor_max: float = 400.0
@export var capacitor_recharge_rate: float = 20.0  # 每秒恢复
@export var max_speed: float = 280.0
@export var warp_speed: float = 3.0  # AU/s
@export var mass: float = 1200000.0
@export var cargo_capacity: float = 500.0
@export var drone_bay: float = 20.0
@export var max_locked_targets: int = 4
@export var signature_radius: float = 40.0  # 信号半径
@export var scan_resolution: float = 400.0  # 扫描分辨率

@export_group("槽位")
@export var high_slots: int = 4
@export var mid_slots: int = 3
@export var low_slots: int = 3
@export var turret_hardpoints: int = 3
@export var launcher_hardpoints: int = 1

@export_group("价格")
@export var base_price: int = 50000
