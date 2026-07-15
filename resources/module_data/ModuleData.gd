extends Resource
class_name ModuleData

## 模块数据定义

enum ModuleSlot { HIGH, MID, LOW }
enum ModuleGroup { 
	SHIELD_BOOSTER, ARMOR_REPAIRER, AFTERBURNER, 
	MICRO_WARP_DRIVE, CAP_RECHARGER, DAMAGE_CONTROL,
	WARP_SCREAMBLER, TRACKING_COMPUTER, SENSOR_BOOSTER
}

@export var module_name: String = "小型护盾回充器"
@export var description: String = "消耗电容来修复护盾"
@export var slot_type: ModuleSlot = ModuleSlot.MID
@export var module_group: ModuleGroup = ModuleGroup.SHIELD_BOOSTER
@export var powergrid_usage: float = 10.0
@export var cpu_usage: float = 10.0
@export var capacitor_usage: float = 30.0  # 每次激活耗电
@export var activation_time: float = 4.0  # 循环时间(秒)
@export var effect_amount: float = 100.0  # 效果量(护盾/装甲修复量等)
@export var base_price: int = 15000
