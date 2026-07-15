extends CanvasLayer
class_name HUD

## 主HUD - 显示飞船状态、目标信息、全景扫描等
## EVE风格界面

@export_group("UI节点引用")
@export var shield_bar: ProgressBar
@export var armor_bar: ProgressBar
@export var hull_bar: ProgressBar
@export var capacitor_bar: ProgressBar
@export var speed_label: Label
@export var ship_name_label: Label
@export var target_info_panel: Control
@export var target_name_label: Label
@export var target_shield_bar: ProgressBar
@export var target_armor_bar: ProgressBar
@export var target_hull_bar: ProgressBar
@export var overview_list: VBoxContainer
@export var capacitor_text_label: Label
@export var isk_label: Label
@export var cargo_label: Label
@export var location_label: Label
@export var message_log: RichTextLabel

var player_ship: PlayerShip = null
var global_ref: Node

func _ready() -> void:
	global_ref = get_node("/root/Global")
	await get_tree().process_frame
	_find_player()
	
	if global_ref:
		if global_ref.has_signal("isk_changed"):
			global_ref.isk_changed.connect(_on_isk_changed)
		if global_ref.has_signal("location_changed"):
			global_ref.location_changed.connect(_on_location_changed)
	
	_update_isk_display()
	_update_location_display()

func _find_player() -> void:
	var ships = get_tree().get_nodes_in_group("player_ship")
	if ships.size() > 0:
		player_ship = ships[0] as PlayerShip
		_connect_ship_signals()

func _connect_ship_signals() -> void:
	if not player_ship:
		return
	player_ship.shield_changed.connect(_update_shield)
	player_ship.armor_changed.connect(_update_armor)
	player_ship.hull_changed.connect(_update_hull)
	player_ship.capacitor_changed.connect(_update_capacitor)
	player_ship.target_locked.connect(_on_target_locked)
	player_ship.target_lost.connect(_on_target_lost)
	
	_update_all()

func _process(_delta: float) -> void:
	if player_ship and is_inside_tree():
		_update_speed()

## ====== 飞船状态更新 ======

func _update_all() -> void:
	if not player_ship:
		return
	_update_shield(player_ship.current_shield, player_ship.max_shield)
	_update_armor(player_ship.current_armor, player_ship.max_armor)
	_update_hull(player_ship.current_hull, player_ship.max_hull)
	_update_capacitor(player_ship.current_capacitor, player_ship.max_capacitor)
	_update_speed()
	if ship_name_label and global_ref:
		ship_name_label.text = global_ref.player_ship_data.get("name", "秃鹫级")
	_update_isk_display()

func _update_shield(current: float, max_value: float) -> void:
	if shield_bar:
		var percent: float = (current / max_value) * 100.0 if max_value > 0 else 0.0
		shield_bar.value = percent

func _update_armor(current: float, max_value: float) -> void:
	if armor_bar:
		var percent: float = (current / max_value) * 100.0 if max_value > 0 else 0.0
		armor_bar.value = percent

func _update_hull(current: float, max_value: float) -> void:
	if hull_bar:
		var percent: float = (current / max_value) * 100.0 if max_value > 0 else 0.0
		hull_bar.value = percent

func _update_capacitor(current: float, max_value: float) -> void:
	if capacitor_bar:
		var percent: float = (current / max_value) * 100.0 if max_value > 0 else 0.0
		capacitor_bar.value = percent
	if capacitor_text_label:
		capacitor_text_label.text = "%.0f / %.0f" % [current, max_value]

func _update_speed() -> void:
	if speed_label and player_ship:
		speed_label.text = "速度: %.0f m/s" % player_ship.current_speed

## ====== 目标信息 ======

func _on_target_locked(target: Ship) -> void:
	if target_info_panel:
		target_info_panel.show()
	if target_name_label:
		target_name_label.text = "目标: " + (target.ship_data.ship_name if target.ship_data else "未知")
	
	target.shield_changed.connect(_update_target_shield)
	target.armor_changed.connect(_update_target_armor)
	target.hull_changed.connect(_update_target_hull)
	target.ship_destroyed.connect(_on_target_destroyed)
	
	_update_target_shield(target.current_shield, target.max_shield)
	_update_target_armor(target.current_armor, target.max_armor)
	_update_target_hull(target.current_hull, target.max_hull)

func _on_target_lost(_target: Ship) -> void:
	if target_info_panel:
		target_info_panel.hide()

func _on_target_destroyed() -> void:
	if target_info_panel:
		target_info_panel.hide()
	add_message("目标已被摧毁!", Color.RED)

func _update_target_shield(current: float, max_value: float) -> void:
	if target_shield_bar:
		target_shield_bar.value = (current / max_value) * 100.0 if max_value > 0 else 0.0

func _update_target_armor(current: float, max_value: float) -> void:
	if target_armor_bar:
		target_armor_bar.value = (current / max_value) * 100.0 if max_value > 0 else 0.0

func _update_target_hull(current: float, max_value: float) -> void:
	if target_hull_bar:
		target_hull_bar.value = (current / max_value) * 100.0 if max_value > 0 else 0.0

## ====== 全景扫描 ======

func _update_overview() -> void:
	pass

## ====== 消息与信息 ======

func add_message(text: String, color: Color = Color.WHITE) -> void:
	if message_log:
		message_log.push_color(color)
		message_log.add_text(text + "\n")
		message_log.pop()

func _on_isk_changed(_value: int) -> void:
	_update_isk_display()

func _on_location_changed(_location_name: String) -> void:
	_update_location_display()

func _update_isk_display() -> void:
	if isk_label and global_ref:
		isk_label.text = "ISK: %s" % _format_isk(global_ref.player_isk)

func _update_location_display() -> void:
	if location_label and global_ref:
		location_label.text = global_ref.player_location

static func _format_isk(amount: int) -> String:
	if amount >= 1000000000:
		return "%.2f B" % (amount / 1000000000.0)
	elif amount >= 1000000:
		return "%.2f M" % (amount / 1000000.0)
	elif amount >= 1000:
		return "%.2f K" % (amount / 1000.0)
	else:
		return str(amount)
