extends ShipModule
class_name StructureRepairer

## 结构维修器 - 消耗电容修复船体结构

func _apply_effect() -> void:
	if owner_ship and owner_ship.current_hull < owner_ship.max_hull:
		owner_ship.current_hull = minf(
			owner_ship.max_hull,
			owner_ship.current_hull + module_data.effect_amount
		)
		owner_ship.hull_changed.emit(owner_ship.current_hull, owner_ship.max_hull)
