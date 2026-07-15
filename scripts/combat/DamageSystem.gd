extends Node
class_name DamageSystem

## 伤害系统 - 处理伤害类型、抗性等

## 伤害类型与抗性计算
## EVE中有四种基础伤害类型：电磁、爆炸、动能、热能
## 护盾/装甲对不同伤害有不同抗性

## 计算实际伤害（考虑抗性）
static func calculate_damage(
	raw_damage: float,
	damage_type: String,
	shield_resistances: Dictionary,
	armor_resistances: Dictionary,
	hull_resistances: Dictionary,
	current_layer: String  # "shield", "armor", "hull"
) -> float:
	var resistance = 0.0
	match current_layer:
		"shield":
			resistance = shield_resistances.get(damage_type, 0.0)
		"armor":
			resistance = armor_resistances.get(damage_type, 0.0)
		"hull":
			resistance = hull_resistances.get(damage_type, 0.0)
	
	return raw_damage * (1.0 - resistance)

## 默认护盾抗性
static func get_default_shield_resistances() -> Dictionary:
	return {
		"电磁": 0.0,
		"爆炸": 0.60,
		"动能": 0.40,
		"热能": 0.20
	}

## 默认装甲抗性
static func get_default_armor_resistances() -> Dictionary:
	return {
		"电磁": 0.60,
		"爆炸": 0.10,
		"动能": 0.35,
		"热能": 0.35
	}

## 默认结构抗性
static func get_default_hull_resistances() -> Dictionary:
	return {
		"电磁": 0.33,
		"爆炸": 0.33,
		"动能": 0.33,
		"热能": 0.33
	}
