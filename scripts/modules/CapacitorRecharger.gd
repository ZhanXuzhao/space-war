extends ShipModule
class_name CapacitorRecharger

## 电容回充器 - 快速恢复电容

func _apply_effect() -> void:
	if owner_ship:
		owner_ship.current_capacitor = minf(
			owner_ship.max_capacitor,
			owner_ship.current_capacitor + module_data.effect_amount * 2.0
		)
		owner_ship.capacitor_changed.emit(owner_ship.current_capacitor, owner_ship.max_capacitor)
