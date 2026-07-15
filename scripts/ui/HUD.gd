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

## 总览更新
var overview_update_timer: float = 0.0
const OVERVIEW_UPDATE_INTERVAL: float = 1.0  # 每秒更新一次
const OVERVIEW_MAX_ENTRIES: int = 20
const OVERVIEW_MAX_RANGE: float = 100000.0  # 最大探测范围

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
	_update_overview()

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

func _process(delta: float) -> void:
	if player_ship and is_inside_tree():
		_update_speed()
	
	# 定时更新总览
	overview_update_timer += delta
	if overview_update_timer >= OVERVIEW_UPDATE_INTERVAL:
		overview_update_timer = 0.0
		_update_overview()

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

## ====== 总览列表（附近飞船、天体） ======

func _update_overview() -> void:
	if not player_ship or not is_inside_tree():
		return
	
	var player_pos: Vector3 = player_ship.global_position
	var entries: Array[Dictionary] = []
	
	# 扫描场景中的所有相关对象
	_scan_nearby_objects(player_pos, entries)
	
	# 按距离排序
	entries.sort_custom(func(a, b): return a["distance"] < b["distance"])
	
	# 限制显示数量
	if entries.size() > OVERVIEW_MAX_ENTRIES:
		entries.resize(OVERVIEW_MAX_ENTRIES)
	
	# 刷新UI列表
	_refresh_overview_list(entries)

func _scan_nearby_objects(player_pos: Vector3, entries: Array[Dictionary]) -> void:
	var root = get_tree().current_scene
	if not root:
		return
	
	# 递归扫描所有子节点
	_scan_node_children(root, player_pos, entries)

func _scan_node_children(node: Node, player_pos: Vector3, entries: Array[Dictionary]) -> void:
	for child in node.get_children():
		# 跳过自身
		if child == player_ship:
			continue
		
		# 检查是否为3D空间中的对象
		if child is Node3D:
			var dist = player_pos.distance_to(child.global_position)
			if dist > OVERVIEW_MAX_RANGE:
				continue
			
			var entry = _classify_object(child, dist)
			if not entry.is_empty():
				entries.append(entry)
		
		# 递归扫描子节点
		_scan_node_children(child, player_pos, entries)

func _classify_object(obj: Node, distance: float) -> Dictionary:
	var result: Dictionary = { "node": obj, "distance": distance, "name": "", "type": "" }
	
	# 飞船（排除玩家）
	if obj is Ship and not obj is PlayerShip:
		if obj.ship_data and obj.ship_data.ship_name:
			result["name"] = obj.ship_data.ship_name
		else:
			result["name"] = "未知飞船"
		result["type"] = "飞船"
		return result
	
	# 小行星
	if obj is Asteroid:
		result["name"] = obj.ore_type + "小行星"
		result["type"] = "小行星"
		return result
	
	# 空间站
	if obj is Station:
		result["name"] = obj.station_name
		result["type"] = "空间站"
		return result
	
	return {}

func _refresh_overview_list(entries: Array[Dictionary]) -> void:
	# 清空列表
	for child in overview_list.get_children():
		child.queue_free()
	
	# 填充列表项
	for entry in entries:
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		# 名称
		var name_label = Label.new()
		name_label.text = entry["name"]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.custom_minimum_size = Vector2(120, 0)
		name_label.theme_override_colors["font_color"] = Color(0.8, 0.8, 0.9, 1)
		name_label.theme_override_font_sizes["font_size"] = 10
		
		# 距离
		var dist_label = Label.new()
		dist_label.text = _format_distance(entry["distance"])
		dist_label.custom_minimum_size = Vector2(80, 0)
		dist_label.theme_override_colors["font_color"] = Color(0.6, 0.6, 0.7, 1)
		dist_label.theme_override_font_sizes["font_size"] = 10
		
		# 类型（带颜色标记）
		var type_label = Label.new()
		type_label.text = entry["type"]
		type_label.custom_minimum_size = Vector2(80, 0)
		type_label.theme_override_font_sizes["font_size"] = 10
		match entry["type"]:
			"飞船":
				type_label.theme_override_colors["font_color"] = Color(1, 0.5, 0.2, 1)
			"小行星":
				type_label.theme_override_colors["font_color"] = Color(0.5, 1, 0.5, 1)
			"空间站":
				type_label.theme_override_colors["font_color"] = Color(0.3, 0.6, 1, 1)
			_:
				type_label.theme_override_colors["font_color"] = Color(0.7, 0.7, 0.7, 1)
		
		row.add_child(name_label)
		row.add_child(dist_label)
		row.add_child(type_label)
		overview_list.add_child(row)

static func _format_distance(distance: float) -> String:
	if distance >= 10000:
		return "%.1f km" % (distance / 1000.0)
	elif distance >= 1000:
		return "%d m" % distance
	else:
		return "%d m" % distance

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
