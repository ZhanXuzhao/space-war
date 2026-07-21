extends ShipModule
class_name ShieldBooster

## 护盾回充器 - 消耗电容修复护盾

func _apply_effect() -> void:
	if owner_ship and owner_ship.current_shield < owner_ship.max_shield:
		var repair_amount = Global.shield_repair_amount * (module_data.effect_amount / 100.0)
		owner_ship.current_shield = minf(
			owner_ship.max_shield,
			owner_ship.current_shield + repair_amount
		)
		owner_ship.shield_changed.emit(owner_ship.current_shield, owner_ship.max_shield)
