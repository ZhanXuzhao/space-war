extends ShipModule
class_name ArmorRepairer

## 装甲修复器 - 消耗电容修复装甲

func _apply_effect() -> void:
	if owner_ship and owner_ship.current_armor < owner_ship.max_armor:
		var repair_amount = Global.armor_repair_amount * (module_data.effect_amount / 100.0)
		owner_ship.current_armor = minf(
			owner_ship.max_armor,
			owner_ship.current_armor + repair_amount
		)
		owner_ship.armor_changed.emit(owner_ship.current_armor, owner_ship.max_armor)
