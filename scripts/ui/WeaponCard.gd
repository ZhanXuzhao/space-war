extends Panel
class_name EquipmentCard

## 装备卡片 - 显示武器或模块的名称、状态、冷却等信息
## 武器：左键分配目标 ｜ 模块：左键启动/停止循环

signal card_clicked(node: Node)

var bound_node: Node = null
var is_weapon: bool = false
var is_module: bool = false

@onready var name_label: Label = $VBox/NameLabel
@onready var type_label: Label = $VBox/TypeLabel
@onready var damage_label: Label = $VBox/DamageLabel
@onready var range_label: Label = $VBox/RangeLabel
@onready var target_label: Label = $VBox/TargetLabel
@onready var status_label: Label = $VBox/StatusLabel
@onready var cooldown_bar: ProgressBar = $VBox/CooldownBar

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)

func _process(_delta: float) -> void:
	if not bound_node or not is_instance_valid(bound_node):
		return
	_update_cooldown()
	_update_status()

func _on_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		if bound_node and is_instance_valid(bound_node):
			card_clicked.emit(bound_node)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_toggle_active()

## 初始化：武器
func setup_weapon(weapon: Weapon) -> void:
	bound_node = weapon
	is_weapon = true
	is_module = false
	
	if not weapon.weapon_data:
		return
	var wd = weapon.weapon_data
	
	name_label.text = wd.weapon_name
	type_label.text = WeaponData.WeaponType.keys()[wd.weapon_type] if wd.weapon_type < WeaponData.WeaponType.size() else "未知"
	damage_label.text = "伤害: %.0f %s" % [wd.damage, wd.damage_type]
	range_label.text = "射程: %.0fkm" % (wd.optimal_range / 1000.0)
	range_label.show()
	
	if not weapon.target_changed.is_connected(_on_weapon_target_changed):
		weapon.target_changed.connect(_on_weapon_target_changed)
	_on_weapon_target_changed(weapon, weapon.assigned_target)
	
	_update_status()
	_update_cooldown()
	_update_style()

## 初始化：模块
func setup_module(mod: ShipModule) -> void:
	bound_node = mod
	is_module = true
	is_weapon = false
	
	if not mod.module_data:
		return
	var md = mod.module_data
	
	name_label.text = md.module_name
	
	var group_names = ModuleData.ModuleGroup.keys()
	var gidx = md.module_group
	type_label.text = group_names[gidx] if gidx < group_names.size() else "模块"
	
	damage_label.text = "修复: %.0f" % md.effect_amount
	range_label.hide()
	target_label.hide()
	
	_update_status()
	_update_cooldown()
	_update_style()

## 右键切换激活/停用
func _toggle_active() -> void:
	if is_weapon and bound_node is Weapon:
		var w = bound_node as Weapon
		w.is_active = not w.is_active
		if not w.is_active:
			w.clear_target()
		_update_style()
		_update_status()
	elif is_module and bound_node is ShipModule:
		var m = bound_node as ShipModule
		if m.is_active:
			m.deactivate()
		else:
			m.activate()
		_update_style()
		_update_status()

## 更新冷却条
func _update_cooldown() -> void:
	if not cooldown_bar or not bound_node:
		return
	
	var on_cooldown = false
	var pct = 0.0
	
	if is_weapon and bound_node is Weapon:
		var w = bound_node as Weapon
		on_cooldown = w.is_on_cooldown
		if on_cooldown:
			pct = (w.cooldown_timer / 3.0) * 100.0
	elif is_module and bound_node is ShipModule:
		var m = bound_node as ShipModule
		on_cooldown = m.is_on_cooldown
		if on_cooldown and m.module_data:
			pct = (m.cooldown_timer / m.module_data.activation_time) * 100.0
	
	if on_cooldown:
		cooldown_bar.value = pct
		cooldown_bar.show()
	else:
		cooldown_bar.value = 0.0
		cooldown_bar.hide()

## 更新状态文字
func _update_status() -> void:
	if not status_label or not bound_node:
		return
	
	var active = false
	if is_weapon and bound_node is Weapon:
		active = (bound_node as Weapon).is_active
	elif is_module and bound_node is ShipModule:
		active = (bound_node as ShipModule).is_active
	
	if not active:
		status_label.text = "已停用"
		status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	elif is_weapon and (bound_node as Weapon).is_on_cooldown:
		status_label.text = "冷却中"
		status_label.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
	elif is_module and (bound_node as ShipModule).is_on_cooldown:
		status_label.text = "循环中"
		status_label.add_theme_color_override("font_color", Color(0.3, 1, 0.3))
	else:
		status_label.text = "就绪"
		status_label.add_theme_color_override("font_color", Color(0.3, 1, 0.3))

## 更新卡片样式（激活/停用）
func _update_style() -> void:
	if not bound_node:
		return
	var active = false
	if is_weapon and bound_node is Weapon:
		active = (bound_node as Weapon).is_active
	elif is_module and bound_node is ShipModule:
		active = (bound_node as ShipModule).is_active
	
	var border_color = Color(0.4, 0.4, 0.4, 0.8)
	if is_module:
		border_color = Color(0.3, 0.9, 0.5, 0.8) if active else Color(0.4, 0.4, 0.4, 0.8)
	elif is_weapon:
		border_color = Color(0.3, 0.8, 1, 1) if active else Color(0.4, 0.4, 0.4, 0.8)
	
	var style = StyleBoxFlat.new()
	if active:
		style.bg_color = Color(0.15, 0.2, 0.25, 0.9)
		style.border_color = border_color
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
	else:
		style.bg_color = Color(0.12, 0.12, 0.15, 0.8)
		style.border_color = border_color
		style.border_width_left = 1
		style.border_width_right = 1
		style.border_width_top = 1
		style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	add_theme_stylebox_override("panel", style)

## 武器目标变更时更新显示
func _on_weapon_target_changed(_weapon: Weapon, target: Ship) -> void:
	if not target_label:
		return
	if target and is_instance_valid(target):
		var name_str = target.ship_data.ship_name if target.ship_data else "未知"
		target_label.text = "→ %s" % name_str
		target_label.add_theme_color_override("font_color", Color(1, 0.5, 0.2))
		target_label.show()
	else:
		target_label.text = ""
		target_label.hide()
