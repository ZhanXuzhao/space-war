extends Resource
class_name ShipData

## 飞船数据定义 - 资源类

## 飞船分类
enum ShipClass { FRIGATE, CRUISER, BATTLESHIP }

## 船型中文名映射
const SHIP_CLASS_NAMES := {
	ShipClass.FRIGATE: "护卫舰",
	ShipClass.CRUISER: "巡洋舰",
	ShipClass.BATTLESHIP: "战列舰",
}

## 各类飞船默认名字池（不含后缀"级"）
const SHIP_CLASS_NAMES_POOL := {
	ShipClass.FRIGATE: ["秃鹫", "镰刀", "匕首", "长矛", "利剑", "战斧", "流星", "彗星", "脉冲"],
	ShipClass.CRUISER: ["风暴", "雷霆", "暗影", "毒蛇", "狂怒", "猎犬", "恶狼", "猛虎"],
	ShipClass.BATTLESHIP: ["末日", "毁灭", "审判", "复仇", "深渊", "巨锤", "铁锤", "磐石"],
}

@export var ship_class: ShipClass = ShipClass.FRIGATE
@export var ship_name: String = "秃鹫级"
@export var description: String = "新手推荐的基础护卫舰"
@export var model_scale: float = 1.0  # 模型缩放系数

@export_group("属性")
@export var hull_hp: float = 800.0
@export var armor_hp: float = 600.0
@export var shield_hp: float = 800.0
@export var capacitor_max: float = 400.0
@export var capacitor_recharge_rate: float = 20.0  # 每秒恢复
@export var max_speed: float = 1000.0
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

# ---- 预设工厂方法 ----

static func create_frigate() -> ShipData:
	var d = ShipData.new()
	d.ship_class = ShipClass.FRIGATE
	d.ship_name = "秃鹫级"
	d.description = "灵活的轻型护卫舰，适合侦察和骚扰任务"
	d.model_scale = 0.33
	d.hull_hp = 800.0
	d.armor_hp = 600.0
	d.shield_hp = 800.0
	d.capacitor_max = 400.0
	d.capacitor_recharge_rate = 20.0
	d.max_speed = 1000.0
	d.warp_speed = 3.0
	d.mass = 1200000.0
	d.cargo_capacity = 500.0
	d.drone_bay = 20.0
	d.max_locked_targets = 4
	d.signature_radius = 40.0
	d.scan_resolution = 400.0
	d.high_slots = 4
	d.mid_slots = 3
	d.low_slots = 3
	d.turret_hardpoints = 4   # 2对
	d.launcher_hardpoints = 1
	d.base_price = 50000
	return d

static func create_cruiser() -> ShipData:
	var d = ShipData.new()
	d.ship_class = ShipClass.CRUISER
	d.ship_name = "风暴级"
	d.description = "多功能巡洋舰，火力与防御兼备"
	d.model_scale = 1.67
	d.hull_hp = 4000.0
	d.armor_hp = 3000.0
	d.shield_hp = 4000.0
	d.capacitor_max = 1200.0
	d.capacitor_recharge_rate = 40.0
	d.max_speed = 500.0
	d.warp_speed = 2.5
	d.mass = 10000000.0
	d.cargo_capacity = 1500.0
	d.drone_bay = 40.0
	d.max_locked_targets = 8
	d.signature_radius = 200.0
	d.scan_resolution = 200.0
	d.high_slots = 6
	d.mid_slots = 5
	d.low_slots = 5
	d.turret_hardpoints = 8   # 4对
	d.launcher_hardpoints = 3
	d.base_price = 300000
	return d

static func create_battleship() -> ShipData:
	var d = ShipData.new()
	d.ship_class = ShipClass.BATTLESHIP
	d.ship_name = "末日级"
	d.description = "重型战列舰，拥有毁灭性的火力和坚不可摧的装甲"
	d.model_scale = 3.33
	d.hull_hp = 120000.0
	d.armor_hp = 100000.0
	d.shield_hp = 80000.0
	d.capacitor_max = 30000.0  # x10
	d.capacitor_recharge_rate = 180.0  # x3
	d.max_speed = 200.0
	d.warp_speed = 2.0
	d.mass = 100000000.0
	d.cargo_capacity = 5000.0
	d.drone_bay = 80.0
	d.max_locked_targets = 12
	d.signature_radius = 500.0
	d.scan_resolution = 80.0
	d.high_slots = 8
	d.mid_slots = 6
	d.low_slots = 7
	d.turret_hardpoints = 16  # 8对
	d.launcher_hardpoints = 5
	d.base_price = 1500000
	return d

## 根据船型获取预设
static func get_preset(cls: ShipClass) -> ShipData:
	match cls:
		ShipClass.FRIGATE:  return create_frigate()
		ShipClass.CRUISER:  return create_cruiser()
		ShipClass.BATTLESHIP: return create_battleship()
	return create_frigate()
