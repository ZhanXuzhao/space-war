extends ShipModule
class_name StructureRepairer

## 结构维修器 - 消耗电容修复船体结构

func _apply_effect() -> void:
	if owner_ship and owner_ship.current_hull < owner_ship.max_hull:
		var repair_amount = Global.structure_repair_amount * (module_data.effect_amount / 100.0)
		owner_ship.current_hull = minf(
			owner_ship.max_hull,
			owner_ship.current_hull + repair_amount
		)
		owner_ship.hull_changed.emit(owner_ship.current_hull, owner_ship.max_hull)
