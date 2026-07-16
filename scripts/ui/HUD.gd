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
@export var target_type_label: Label
@export var target_dist_label: Label
@export var target_shield_bar: ProgressBar
@export var target_armor_bar: ProgressBar
@export var target_hull_bar: ProgressBar
@export var btn_approach: Button
@export var btn_orbit: Button
@export var btn_warp: Button
@export var btn_cancel: Button
@export var overview_list: VBoxContainer
@export var capacitor_text_label: Label
@export var shield_text_label: Label
@export var armor_text_label: Label
@export var hull_text_label: Label
@export var isk_label: Label
@export var cargo_label: Label
@export var location_label: Label
@export var message_log: VBoxContainer
@export var context_menu: OverviewContextMenu
@export var spawn_button: Button
@export var cam_dist_label: Label
@export var menu_panel: Panel

var player_ship: PlayerShip = null
var global_ref: Node
var enemy_spawner: EnemySpawner = null
var _target_node: Node = null  # 当前目标面板显示的节点

## 总览更新
var overview_update_timer: float = 0.0
const OVERVIEW_UPDATE_INTERVAL: float = 1.0  # 每秒更新一次
const OVERVIEW_MAX_ENTRIES: int = 20
const OVERVIEW_MAX_RANGE: float = 100000.0  # 最大探测范围

## 排序状态
enum SortColumn { NAME, DISTANCE, SPEED, TYPE }
var sort_column: SortColumn = SortColumn.DISTANCE
var sort_ascending: bool = true
var _name_header: Label
var _dist_header: Label
var _speed_header: Label
var _type_header: Label

func _ready() -> void:
	global_ref = get_node("/root/Global")
	await get_tree().process_frame
	
	# 手动查找节点（场景 NodePath 绑定有时不生效）
	overview_list = get_node_or_null("OverviewPanel/ScrollContainer/OverviewList") as VBoxContainer
	target_info_panel = get_node_or_null("TargetPanel") as Control
	target_name_label = get_node_or_null("TargetPanel/TargetName") as Label
	target_type_label = get_node_or_null("TargetPanel/TargetType") as Label
	target_dist_label = get_node_or_null("TargetPanel/TargetDistLabel") as Label
	target_shield_bar = get_node_or_null("TargetPanel/TargetShieldBar") as ProgressBar
	target_armor_bar = get_node_or_null("TargetPanel/TargetArmorBar") as ProgressBar
	target_hull_bar = get_node_or_null("TargetPanel/TargetHullBar") as ProgressBar
	btn_approach = get_node_or_null("TargetPanel/BtnApproach") as Button
	btn_orbit = get_node_or_null("TargetPanel/BtnOrbit") as Button
	btn_warp = get_node_or_null("TargetPanel/BtnWarp") as Button
	btn_cancel = get_node_or_null("TargetPanel/BtnCancel") as Button
	cam_dist_label = get_node_or_null("TopBar/CamDistLabel") as Label
	# 手动查找飞船状态条和文字标签（场景 NodePath 绑定不生效）
	if not shield_bar:
		shield_bar = get_node_or_null("ShipStatusPanel/ShieldBar") as ProgressBar
	if not armor_bar:
		armor_bar = get_node_or_null("ShipStatusPanel/ArmorBar") as ProgressBar
	if not hull_bar:
		hull_bar = get_node_or_null("ShipStatusPanel/HullBar") as ProgressBar
	if not capacitor_bar:
		capacitor_bar = get_node_or_null("ShipStatusPanel/CapacitorBar") as ProgressBar
	if not shield_text_label:
		shield_text_label = get_node_or_null("ShipStatusPanel/ShieldLabel") as Label
	if not armor_text_label:
		armor_text_label = get_node_or_null("ShipStatusPanel/ArmorLabel") as Label
	if not hull_text_label:
		hull_text_label = get_node_or_null("ShipStatusPanel/HullLabel") as Label
	if not capacitor_text_label:
		capacitor_text_label = get_node_or_null("ShipStatusPanel/CapacitorLabel") as Label
	# 手动查找速度标签
	if not speed_label:
		speed_label = get_node_or_null("ShipStatusPanel/SpeedLabel") as Label
	# 手动查找召唤按钮和消息日志
	if not spawn_button:
		spawn_button = get_node_or_null("MenuPanel/SpawnButton") as Button
	if not message_log:
		message_log = get_node_or_null("MessageLog") as VBoxContainer
	
	# 连接 DraggablePanel 布局变更信号 → 保存面板位置
	for panel_name in ["OverviewPanel", "TargetPanel", "ShipStatusPanel"]:
		var p = get_node_or_null(panel_name)
		if p and p.has_signal("layout_changed"):
			p.layout_changed.connect(_save_panel_layout)
	
	# 总览空白区域点击 → 清除相机锁定
	if overview_list:
		overview_list.mouse_filter = Control.MOUSE_FILTER_STOP
		overview_list.gui_input.connect(_on_overview_empty_click)
	_name_header = get_node_or_null("OverviewPanel/ColumnHeader/NameHeader") as Label
	_dist_header = get_node_or_null("OverviewPanel/ColumnHeader/DistHeader") as Label
	_speed_header = get_node_or_null("OverviewPanel/ColumnHeader/SpeedHeader") as Label
	_type_header = get_node_or_null("OverviewPanel/ColumnHeader/TypeHeader") as Label
	
	# 连接列标题点击
	if _name_header:
		_name_header.mouse_filter = Control.MOUSE_FILTER_STOP
		_name_header.gui_input.connect(_on_header_click.bind(SortColumn.NAME))
	if _dist_header:
		_dist_header.mouse_filter = Control.MOUSE_FILTER_STOP
		_dist_header.gui_input.connect(_on_header_click.bind(SortColumn.DISTANCE))
	if _type_header:
		_type_header.mouse_filter = Control.MOUSE_FILTER_STOP
		_type_header.gui_input.connect(_on_header_click.bind(SortColumn.TYPE))
	if _speed_header:
		_speed_header.mouse_filter = Control.MOUSE_FILTER_STOP
		_speed_header.gui_input.connect(_on_header_click.bind(SortColumn.SPEED))
	
	_update_sort_indicators()
	
	# 加载保存的面板布局
	_load_panel_layout()
	
	_find_player()
	
	if global_ref:
		if global_ref.has_signal("isk_changed"):
			global_ref.isk_changed.connect(_on_isk_changed)
		if global_ref.has_signal("location_changed"):
			global_ref.location_changed.connect(_on_location_changed)
	
	_update_isk_display()
	_update_location_display()
	_update_overview()
	
	# 连接右键菜单
	if context_menu:
		context_menu.menu_option_selected.connect(_on_context_menu_action)
	
	# 连接目标操作按钮
	if btn_approach:
		btn_approach.pressed.connect(_on_btn_approach)
	if btn_orbit:
		btn_orbit.pressed.connect(_on_btn_orbit)
	if btn_warp:
		btn_warp.pressed.connect(_on_btn_warp)
	if btn_cancel:
		btn_cancel.pressed.connect(_on_btn_cancel)
	
	# 连接战斗日志信号
	var _global = get_node("/root/Global")
	if _global and _global.has_signal("combat_log"):
		_global.combat_log.connect(_on_combat_log)
	
	# 连接召唤按钮
	if spawn_button:
		spawn_button.pressed.connect(_on_spawn_button_pressed)
		print("HUD: spawn_button 已绑定，手动召唤敌人功能可用")
		# 找到 EnemySpawner
		enemy_spawner = get_node_or_null("/root/SpaceWar/EnemySpawner") as EnemySpawner
		if not enemy_spawner:
			# 延迟再试
			await get_tree().create_timer(0.5).timeout
			enemy_spawner = get_node_or_null("/root/SpaceWar/EnemySpawner") as EnemySpawner
	else:
		print("HUD: spawn_button 未绑定，无法手动召唤敌人")

func _find_player() -> void:
	var ships = get_tree().get_nodes_in_group("player_ship")
	if ships.size() > 0:
		player_ship = ships[0] as PlayerShip
	if not player_ship:
		player_ship = get_node_or_null("/root/SpaceWar/PlayerShip") as PlayerShip
	if player_ship:
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
		_update_target_distance()
		_update_cam_dist()
	
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
	if shield_text_label:
		shield_text_label.text = "护盾: %.0f / %.0f" % [current, max_value]

func _update_armor(current: float, max_value: float) -> void:
	if armor_bar:
		var percent: float = (current / max_value) * 100.0 if max_value > 0 else 0.0
		armor_bar.value = percent
	if armor_text_label:
		armor_text_label.text = "装甲: %.0f / %.0f" % [current, max_value]

func _update_hull(current: float, max_value: float) -> void:
	if hull_bar:
		var percent: float = (current / max_value) * 100.0 if max_value > 0 else 0.0
		hull_bar.value = percent
	if hull_text_label:
		hull_text_label.text = "结构: %.0f / %.0f" % [current, max_value]

func _update_capacitor(current: float, max_value: float) -> void:
	if capacitor_bar:
		var percent: float = (current / max_value) * 100.0 if max_value > 0 else 0.0
		capacitor_bar.value = percent
	if capacitor_text_label:
		capacitor_text_label.text = "电容: %.0f / %.0f" % [current, max_value]

func _update_speed() -> void:
	if speed_label and player_ship:
		speed_label.text = "速度: %.0f m/s" % player_ship.current_speed

## ====== 目标信息 ======

func _on_target_locked(target: Ship) -> void:
	# 断开上一个目标的信号
	if _target_node and is_instance_valid(_target_node) and _target_node is Ship:
		var old = _target_node as Ship
		if old.shield_changed.is_connected(_update_target_shield):
			old.shield_changed.disconnect(_update_target_shield)
		if old.armor_changed.is_connected(_update_target_armor):
			old.armor_changed.disconnect(_update_target_armor)
		if old.hull_changed.is_connected(_update_target_hull):
			old.hull_changed.disconnect(_update_target_hull)
		if old.ship_destroyed.is_connected(_on_target_destroyed):
			old.ship_destroyed.disconnect(_on_target_destroyed)
	
	_target_node = target
	if target_info_panel:
		target_info_panel.show()
	
	var name_str = target.ship_data.ship_name if target.ship_data else "未知飞船"
	if target_name_label:
		target_name_label.text = name_str
	if target_type_label:
		match target.faction:
			Ship.Faction.NPC_HOSTILE:
				target_type_label.text = "敌对"
				target_type_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
			Ship.Faction.NPC_FRIENDLY:
				target_type_label.text = "友好"
				target_type_label.add_theme_color_override("font_color", Color(0.3, 1, 0.3))
			_:
				target_type_label.text = "中立"
				target_type_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	
	target.shield_changed.connect(_update_target_shield)
	target.armor_changed.connect(_update_target_armor)
	target.hull_changed.connect(_update_target_hull)
	target.ship_destroyed.connect(_on_target_destroyed)
	
	_update_target_shield(target.current_shield, target.max_shield)
	_update_target_armor(target.current_armor, target.max_armor)
	_update_target_hull(target.current_hull, target.max_hull)

func _update_target_distance() -> void:
	if not target_dist_label or not _target_node or not is_instance_valid(_target_node):
		return
	if not player_ship:
		return
	var dist = player_ship.global_position.distance_to(_target_node.global_position)
	target_dist_label.text = "距离: " + _format_distance(dist)

func _on_target_lost(_target: Ship) -> void:
	if target_info_panel:
		target_info_panel.hide()
	_target_node = null

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
	
	# 按当前排序列和方向排序
	_sort_entries(entries)
	
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
	var result: Dictionary = { "node": obj, "distance": distance, "name": "", "type": "", "speed": 0.0 }
	
	# 飞船（排除玩家）
	if obj is Ship and not obj is PlayerShip:
		if obj.ship_data and obj.ship_data.ship_name:
			result["name"] = obj.ship_data.ship_name
		else:
			result["name"] = "未知飞船"
		result["type"] = "飞船"
		result["speed"] = obj.current_speed
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
	if not overview_list:
		return
		return
	# 清空列表
	for child in overview_list.get_children():
		child.queue_free()
	
	# 填充列表项
	for i in range(entries.size()):
		var entry = entries[i]
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		# 名称
		var name_label = Label.new()
		name_label.text = entry["name"]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9, 1))
		name_label.add_theme_font_size_override("font_size", 10)
		
		# 距离
		var dist_label = Label.new()
		dist_label.text = _format_distance(entry["distance"])
		dist_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dist_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7, 1))
		dist_label.add_theme_font_size_override("font_size", 10)
		
		# 速度
		var speed_label = Label.new()
		speed_label.text = _format_speed(entry["speed"])
		speed_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		speed_label.add_theme_color_override("font_color", Color(0.3, 1, 0.5, 1))
		speed_label.add_theme_font_size_override("font_size", 10)
		
		# 类型
		var type_label = Label.new()
		type_label.text = entry["type"]
		type_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		type_label.add_theme_font_size_override("font_size", 10)
		match entry["type"]:
			"飞船":
				type_label.add_theme_color_override("font_color", Color(1, 0.5, 0.2, 1))
			"小行星":
				type_label.add_theme_color_override("font_color", Color(0.5, 1, 0.5, 1))
			"空间站":
				type_label.add_theme_color_override("font_color", Color(0.3, 0.6, 1, 1))
			_:
				type_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
		
		# 点击 → 锁定/选择目标
		name_label.gui_input.connect(_on_overview_label_input.bind(entry))
		dist_label.gui_input.connect(_on_overview_label_input.bind(entry))
		speed_label.gui_input.connect(_on_overview_label_input.bind(entry))
		type_label.gui_input.connect(_on_overview_label_input.bind(entry))
		
		name_label.mouse_filter = Control.MOUSE_FILTER_STOP
		dist_label.mouse_filter = Control.MOUSE_FILTER_STOP
		speed_label.mouse_filter = Control.MOUSE_FILTER_STOP
		type_label.mouse_filter = Control.MOUSE_FILTER_STOP
		
		row.add_child(name_label)
		row.add_child(dist_label)
		row.add_child(speed_label)
		row.add_child(type_label)
		overview_list.add_child(row)

static func _format_speed(speed: float) -> String:
	if speed >= 100:
		return "%.0f" % speed
	elif speed >= 1:
		return "%.1f" % speed
	else:
		return "0"

static func _format_distance(distance: float) -> String:
	if distance >= 10000:
		return "%.1f km" % (distance / 1000.0)
	elif distance >= 1000:
		return "%d m" % distance
	else:
		return "%d m" % distance

## ====== 总览排序（点击表头切换） ======

func _on_header_click(event: InputEvent, column: SortColumn) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if sort_column == column:
			sort_ascending = not sort_ascending
		else:
			sort_column = column
			sort_ascending = true
		_update_sort_indicators()
		_update_overview()

func _sort_entries(entries: Array[Dictionary]) -> void:
	match sort_column:
		SortColumn.NAME:
			if sort_ascending:
				entries.sort_custom(func(a, b): return a["name"] < b["name"])
			else:
				entries.sort_custom(func(a, b): return a["name"] > b["name"])
		SortColumn.DISTANCE:
			if sort_ascending:
				entries.sort_custom(func(a, b): return a["distance"] < b["distance"])
			else:
				entries.sort_custom(func(a, b): return a["distance"] > b["distance"])
		SortColumn.TYPE:
			if sort_ascending:
				entries.sort_custom(func(a, b): return a["type"] < b["type"])
			else:
				entries.sort_custom(func(a, b): return a["type"] > b["type"])
		SortColumn.SPEED:
			if sort_ascending:
				entries.sort_custom(func(a, b): return a["speed"] < b["speed"])
			else:
				entries.sort_custom(func(a, b): return a["speed"] > b["speed"])

func _update_sort_indicators() -> void:
	var arrow_up = " ▲"
	var arrow_down = " ▼"
	
	if _name_header:
		if sort_column == SortColumn.NAME:
			_name_header.text = "名称" + (arrow_up if sort_ascending else arrow_down)
		else:
			_name_header.text = "名称"
	
	if _dist_header:
		if sort_column == SortColumn.DISTANCE:
			_dist_header.text = "距离" + (arrow_up if sort_ascending else arrow_down)
		else:
			_dist_header.text = "距离"
	
	if _type_header:
		if sort_column == SortColumn.TYPE:
			_type_header.text = "类型" + (arrow_up if sort_ascending else arrow_down)
		else:
			_type_header.text = "类型"
	if _speed_header:
		if sort_column == SortColumn.SPEED:
			_speed_header.text = "速度" + (arrow_up if sort_ascending else arrow_down)
		else:
			_speed_header.text = "速度"

## ====== 总览交互（点击行 = 锁定/右键菜单） ======

## Alt+点击空白区域 → 相机解锁回自身飞船
func _on_overview_empty_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if event.alt_pressed and player_ship:
			player_ship.clear_camera_focus()

func _on_overview_label_input(event: InputEvent, entry: Dictionary) -> void:
	if not player_ship:
		return
	
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Alt+左键 → 相机锁定/解锁
		if event.alt_pressed:
			var target_node = entry.get("node")
			if target_node is Node3D and is_instance_valid(target_node):
				player_ship.set_camera_focus(target_node)
			else:
				player_ship.clear_camera_focus()
		else:
			_on_overview_left_click(entry)
	
	# 右键点击 → 弹出右键菜单
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_on_overview_right_click(entry, event)

func _on_overview_left_click(entry: Dictionary) -> void:
	var target_node = entry.get("node")
	if not target_node or not is_instance_valid(target_node):
		player_ship.clear_camera_focus()
		return
	
	# 显示目标信息（不锁定）
	_show_target_info(target_node)

## 直接显示目标信息面板（不锁定目标）
func _show_target_info(node: Node) -> void:
	if not node or not is_instance_valid(node):
		return
	if not target_info_panel:
		return
	
	_target_node = node
	target_info_panel.show()
	
	var name_str = ""
	if node is Ship:
		name_str = node.ship_data.ship_name if node.ship_data else "未知飞船"
		if target_type_label:
			match node.faction:
				Ship.Faction.NPC_HOSTILE:
					target_type_label.text = "敌对"
					target_type_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
				Ship.Faction.NPC_FRIENDLY:
					target_type_label.text = "友好"
					target_type_label.add_theme_color_override("font_color", Color(0.3, 1, 0.3))
				_:
					target_type_label.text = "中立"
					target_type_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	elif node is Asteroid:
		name_str = node.ore_type + "小行星"
		if target_type_label:
			target_type_label.text = "小行星"
			target_type_label.add_theme_color_override("font_color", Color(0.5, 1, 0.5))
	elif node is Station:
		name_str = node.station_name
		if target_type_label:
			target_type_label.text = "空间站"
			target_type_label.add_theme_color_override("font_color", Color(0.3, 0.6, 1))
	
	if target_name_label:
		target_name_label.text = name_str

func _on_overview_right_click(entry: Dictionary, event: InputEventMouseButton) -> void:
	var target_node = entry.get("node")
	if not target_node or not is_instance_valid(target_node):
		return
	if not context_menu:
		return
	
	# 计算全局屏幕坐标
	var label_local_pos = Vector2.ZERO
	if event is InputEventMouseButton:
		label_local_pos = event.position
	var global_pos = get_viewport().get_mouse_position()
	context_menu.show_for_target(target_node, global_pos)

## 处理右键菜单的回调
func _on_context_menu_action(action: String, target_node: Node) -> void:
	if not player_ship or not target_node or not is_instance_valid(target_node):
		return
	
	match action:
		"lock":
			if target_node is Ship:
				player_ship.try_lock_ship(target_node)
				var name_str = target_node.ship_data.ship_name if target_node.ship_data else "未知"
				add_message("锁定: " + name_str, Color(0.3, 0.8, 1))
		
		"attack":
			if target_node is Ship:
				# 锁定并设为攻击目标
				player_ship.try_lock_ship(target_node)
				player_ship.set_active_target(target_node)
				var name_str = target_node.ship_data.ship_name if target_node.ship_data else "未知"
				add_message("攻击目标: " + name_str, Color(1, 0.3, 0.3))
				# 自动开火
				player_ship.set_auto_fire(true)
		
		"approach":
			if target_node is Node3D:
				player_ship.order_move_to(target_node.global_position)
				var name_str = ""
				if target_node is Ship and target_node.ship_data:
					name_str = target_node.ship_data.ship_name
				elif target_node is Asteroid:
					name_str = target_node.ore_type + "小行星"
				elif target_node is Station:
					name_str = target_node.station_name
				else:
					name_str = "目标"
				add_message("接近: " + name_str, Color(0.5, 1, 0.5))
		
		"unlock":
			if target_node is Ship:
				player_ship.unlock_target(target_node)
				var name_str = target_node.ship_data.ship_name if target_node.ship_data else "未知"
				add_message("解锁: " + name_str, Color(0.7, 0.7, 0.7))
		
		"set_active":
			if target_node is Ship:
				player_ship.set_active_target(target_node)
				var name_str = target_node.ship_data.ship_name if target_node.ship_data else "未知"
				add_message("当前目标: " + name_str, Color(0.3, 0.8, 1))
		
		"mine":
			if target_node is Asteroid:
				player_ship.order_move_to(target_node.global_position)
				add_message("前往采矿: " + entry_name(target_node), Color(0.5, 1, 0.5))
		
		"dock":
			if target_node is Station:
				player_ship.order_move_to(target_node.global_position)
				add_message("前往停靠: " + target_node.station_name, Color(0.3, 0.6, 1))

## ====== 目标操作按钮 ======

func _on_btn_approach() -> void:
	if not player_ship or not _target_node or not is_instance_valid(_target_node):
		return
	if _target_node is Node3D:
		player_ship.order_move_to(_target_node.global_position)
		add_message("靠近: " + entry_name(_target_node), Color(0.3, 0.8, 1))

func _on_btn_orbit() -> void:
	if not player_ship or not _target_node or not is_instance_valid(_target_node):
		return
	if _target_node is Node3D:
		player_ship.order_orbit(_target_node)
		add_message("环绕: " + entry_name(_target_node), Color(0.3, 0.8, 1))

func _on_btn_warp() -> void:
	if not player_ship or not _target_node or not is_instance_valid(_target_node):
		return
	if _target_node is Node3D:
		player_ship.warp_to(_target_node.global_position)
		add_message("跃迁: " + entry_name(_target_node), Color(0.3, 0.8, 1))

func _on_btn_cancel() -> void:
	if not player_ship:
		return
	# 取消环绕
	if player_ship.orbit_target:
		player_ship.cancel_orbit()
		add_message("已取消环绕", Color(1, 0.6, 0.3))
	# 清除移动指令
	player_ship.has_move_order = false
	player_ship.current_speed = 0.0

## ====== 召唤敌舰按钮 ======

func _on_spawn_button_pressed() -> void:
	if enemy_spawner:
		enemy_spawner.spawn_wave()
		add_message("召唤一波敌舰!", Color(1, 0.3, 0.3))
	else:
		# 再找一次
		enemy_spawner = get_node_or_null("/root/SpaceWar/EnemySpawner") as EnemySpawner
		if enemy_spawner:
			enemy_spawner.spawn_wave()
			add_message("召唤一波敌舰!", Color(1, 0.3, 0.3))
		else:
			add_message("错误: 找不到 EnemySpawner!", Color.RED)

static func entry_name(node: Node) -> String:
	if node is Ship and node.ship_data:
		return node.ship_data.ship_name
	if node is Asteroid:
		return node.ore_type + "小行星"
	if node is Station:
		return node.station_name
	return "目标"

## ====== 面板布局保存/加载 ======

const PANEL_SAVE_PATH: String = "user://panel_layout.cfg"

func _save_panel_layout() -> void:
	var cfg = ConfigFile.new()
	var overview = get_node_or_null("OverviewPanel")
	var target = get_node_or_null("TargetPanel")
	var ship_status = get_node_or_null("ShipStatusPanel")
	if overview:
		cfg.set_value("OverviewPanel", "offset_left", overview.offset_left)
		cfg.set_value("OverviewPanel", "offset_top", overview.offset_top)
		cfg.set_value("OverviewPanel", "offset_right", overview.offset_right)
		cfg.set_value("OverviewPanel", "offset_bottom", overview.offset_bottom)
	if target:
		cfg.set_value("TargetPanel", "offset_left", target.offset_left)
		cfg.set_value("TargetPanel", "offset_top", target.offset_top)
		cfg.set_value("TargetPanel", "offset_right", target.offset_right)
		cfg.set_value("TargetPanel", "offset_bottom", target.offset_bottom)
	if ship_status:
		cfg.set_value("ShipStatusPanel", "offset_left", ship_status.offset_left)
		cfg.set_value("ShipStatusPanel", "offset_top", ship_status.offset_top)
		cfg.set_value("ShipStatusPanel", "offset_right", ship_status.offset_right)
		cfg.set_value("ShipStatusPanel", "offset_bottom", ship_status.offset_bottom)
	cfg.save(PANEL_SAVE_PATH)

func _load_panel_layout() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(PANEL_SAVE_PATH) != OK:
		return
	var overview = get_node_or_null("OverviewPanel")
	var target = get_node_or_null("TargetPanel")
	var ship_status = get_node_or_null("ShipStatusPanel")
	if overview:
		if cfg.has_section_key("OverviewPanel", "offset_left"):
			overview.offset_left = cfg.get_value("OverviewPanel", "offset_left")
			overview.offset_top = cfg.get_value("OverviewPanel", "offset_top")
			overview.offset_right = cfg.get_value("OverviewPanel", "offset_right")
			overview.offset_bottom = cfg.get_value("OverviewPanel", "offset_bottom")
	if target:
		if cfg.has_section_key("TargetPanel", "offset_left"):
			target.offset_left = cfg.get_value("TargetPanel", "offset_left")
			target.offset_top = cfg.get_value("TargetPanel", "offset_top")
			target.offset_right = cfg.get_value("TargetPanel", "offset_right")
			target.offset_bottom = cfg.get_value("TargetPanel", "offset_bottom")
	if ship_status:
		if cfg.has_section_key("ShipStatusPanel", "offset_left"):
			ship_status.offset_left = cfg.get_value("ShipStatusPanel", "offset_left")
			ship_status.offset_top = cfg.get_value("ShipStatusPanel", "offset_top")
			ship_status.offset_right = cfg.get_value("ShipStatusPanel", "offset_right")
			ship_status.offset_bottom = cfg.get_value("ShipStatusPanel", "offset_bottom")

## ====== 消息与信息 ======

func _update_cam_dist() -> void:
	if not cam_dist_label or not player_ship:
		return
	if player_ship.has_method("get_cam_distance"):
		var dist = player_ship.get_cam_distance()
		cam_dist_label.text = "镜头: " + _format_distance(dist)

func add_message(text: String, color: Color = Color.WHITE) -> void:
	if not message_log:
		return
	# 创建消息标签
	var label = Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 12)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# 插入到顶部
	message_log.add_child(label)
	message_log.move_child(label, 0)
	# 5秒后自动移除
	var timer := get_tree().create_timer(5.0)
	timer.timeout.connect(func():
		if is_instance_valid(label):
			label.queue_free()
	, CONNECT_ONE_SHOT)

## 接收战斗日志消息并显示到UI
func _on_combat_log(message: String, color: Color) -> void:
	add_message(message, color)

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
