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
@export var btn_attack: Button
@export var overview_list: VBoxContainer
@export var capacitor_text_label: Label
@export var shield_text_label: Label
@export var armor_text_label: Label
@export var hull_text_label: Label
@export var cargo_label: Label
@export var auto_lock_check: CheckBox
@export var auto_attack_check: CheckBox
@export var message_log: VBoxContainer
@export var context_menu: OverviewContextMenu
@export var spawn_button: Button
@export var new_game_button: Button
@export var restart_game_button: Button
@export var menu_panel: Panel
@export var btn_lock: Button
@export var btn_unlock: Button
@export var locked_panel: Control
@export var locked_list: HBoxContainer

## 装备面板
@export var equipment_panel: Panel
@export var equipment_list: HBoxContainer

## 锁定目标跟踪
var watched_targets: Array[Ship] = []
var _watched_target_data: Dictionary = {}  # Ship → {card: Control, shield_sig, armor_sig, hull_sig, capacitor_sig, destroy_sig}
var _selected_locked_target: Ship = null

## 装备面板跟踪
var _equipment_cards: Array[EquipmentCard] = []
var _equipment_update_timer: float = 0.0
const EQUIPMENT_UPDATE_INTERVAL: float = 0.2

## 自动锁定/攻击
var _auto_lock_timer: float = 0.0
const AUTO_LOCK_INTERVAL: float = 1.0
var _auto_attack_timer: float = 0.0
const AUTO_ATTACK_INTERVAL: float = 1.0
var _auto_lock_enabled: bool = true
var _auto_attack_enabled: bool = true

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
	target_name_label = get_node_or_null("TargetPanel/VBoxContainer/TargetName") as Label
	target_type_label = get_node_or_null("TargetPanel/VBoxContainer/TargetType") as Label
	target_dist_label = get_node_or_null("TargetPanel/VBoxContainer/TargetDistLabel") as Label
	target_shield_bar = get_node_or_null("TargetPanel/VBoxContainer/TargetShieldBar") as ProgressBar
	target_armor_bar = get_node_or_null("TargetPanel/VBoxContainer/TargetArmorBar") as ProgressBar
	target_hull_bar = get_node_or_null("TargetPanel/VBoxContainer/TargetHullBar") as ProgressBar
	btn_approach = get_node_or_null("TargetPanel/VBoxContainer/ActionBtnHBox/BtnApproach") as Button
	btn_orbit = get_node_or_null("TargetPanel/VBoxContainer/ActionBtnHBox/BtnOrbit") as Button
	btn_warp = get_node_or_null("TargetPanel/VBoxContainer/ActionBtnHBox/BtnWarp") as Button
	btn_attack = get_node_or_null("TargetPanel/VBoxContainer/BtnAttack") as Button
	btn_lock = get_node_or_null("TargetPanel/VBoxContainer/LockBtnHBox/BtnLock") as Button
	btn_unlock = get_node_or_null("TargetPanel/VBoxContainer/LockBtnHBox/BtnUnlock") as Button
	locked_panel = get_node_or_null("LockedPanel") as Control
	locked_list = get_node_or_null("LockedPanel/ScrollContainer/LockedList") as HBoxContainer
	# 手动查找装备面板
	equipment_panel = get_node_or_null("EquipmentPanel") as Panel
	equipment_list = get_node_or_null("EquipmentPanel/ScrollContainer/EquipmentList") as HBoxContainer
	# 手动查找飞船状态条和文字标签（场景 NodePath 绑定不生效）
	if not shield_bar:
		shield_bar = get_node_or_null("ShipStatusPanel/VBoxContainer/ShieldBar") as ProgressBar
	if not armor_bar:
		armor_bar = get_node_or_null("ShipStatusPanel/VBoxContainer/ArmorBar") as ProgressBar
	if not hull_bar:
		hull_bar = get_node_or_null("ShipStatusPanel/VBoxContainer/HullBar") as ProgressBar
	if not capacitor_bar:
		capacitor_bar = get_node_or_null("ShipStatusPanel/VBoxContainer/CapacitorBar") as ProgressBar
	if not shield_text_label:
		shield_text_label = get_node_or_null("ShipStatusPanel/VBoxContainer/ShieldLabel") as Label
	if not armor_text_label:
		armor_text_label = get_node_or_null("ShipStatusPanel/VBoxContainer/ArmorLabel") as Label
	if not hull_text_label:
		hull_text_label = get_node_or_null("ShipStatusPanel/VBoxContainer/HullLabel") as Label
	if not capacitor_text_label:
		capacitor_text_label = get_node_or_null("ShipStatusPanel/VBoxContainer/CapacitorLabel") as Label
	# 手动查找速度标签
	if not speed_label:
		speed_label = get_node_or_null("ShipStatusPanel/VBoxContainer/SpeedLabel") as Label
	# 手动查找自动锁定/攻击勾选框
	if not auto_lock_check:
		auto_lock_check = get_node_or_null("ShipStatusPanel/VBoxContainer/AutoCheckHBox/AutoLockCheck") as CheckBox
	if not auto_attack_check:
		auto_attack_check = get_node_or_null("ShipStatusPanel/VBoxContainer/AutoCheckHBox/AutoAttackCheck") as CheckBox
	# 连接勾选框信号（必须在 _load_panel_layout 之前，确保加载时能触发回调）
	if auto_lock_check:
		auto_lock_check.toggled.connect(_on_auto_lock_toggled)
	if auto_attack_check:
		auto_attack_check.toggled.connect(_on_auto_attack_toggled)
	# 手动查找召唤按钮、新建游戏按钮和消息日志
	if not spawn_button:
		spawn_button = get_node_or_null("MenuPanel/SpawnButton") as Button
	if not new_game_button:
		new_game_button = get_node_or_null("MenuPanel/NewGameButton") as Button
	if not restart_game_button:
		restart_game_button = get_node_or_null("MenuPanel/RestartGameButton") as Button
	if not message_log:
		message_log = get_node_or_null("MessageLog/ScrollContainer/MessageList") as VBoxContainer
	
	# 连接 DraggablePanel 布局变更信号 → 保存面板位置
	for panel_name in ["OverviewPanel", "TargetPanel", "ShipStatusPanel", "LockedPanel", "EquipmentPanel", "MessageLog"]:
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
	if btn_attack:
		btn_attack.pressed.connect(_on_btn_attack)
	
	# 连接锁定/解除锁定按钮
	if btn_lock:
		btn_lock.pressed.connect(_on_btn_lock_pressed)
	if btn_unlock:
		btn_unlock.pressed.connect(_on_btn_unlock_pressed)
	
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
	
	# 连接新建游戏按钮
	if new_game_button:
		new_game_button.pressed.connect(_on_new_game_pressed)
	
	# 连接重开游戏按钮
	if restart_game_button:
		restart_game_button.pressed.connect(_on_restart_game_pressed)

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
	# 先断开可能残留的旧连接，再重新连接（防止 repeat connect 错误）
	if player_ship.shield_changed.is_connected(_update_shield):
		player_ship.shield_changed.disconnect(_update_shield)
	if player_ship.armor_changed.is_connected(_update_armor):
		player_ship.armor_changed.disconnect(_update_armor)
	if player_ship.hull_changed.is_connected(_update_hull):
		player_ship.hull_changed.disconnect(_update_hull)
	if player_ship.capacitor_changed.is_connected(_update_capacitor):
		player_ship.capacitor_changed.disconnect(_update_capacitor)
	if player_ship.target_locked.is_connected(_on_target_locked):
		player_ship.target_locked.disconnect(_on_target_locked)
	if player_ship.target_lost.is_connected(_on_target_lost):
		player_ship.target_lost.disconnect(_on_target_lost)
	
	player_ship.shield_changed.connect(_update_shield)
	player_ship.armor_changed.connect(_update_armor)
	player_ship.hull_changed.connect(_update_hull)
	player_ship.capacitor_changed.connect(_update_capacitor)
	player_ship.target_locked.connect(_on_target_locked)
	player_ship.target_lost.connect(_on_target_lost)
	
	_update_all()
	_refresh_equipment_panel()

func _process(delta: float) -> void:
	if player_ship and is_inside_tree():
		_update_speed()
		_update_target_distance()
	
	# 定时更新总览
	overview_update_timer += delta
	if overview_update_timer >= OVERVIEW_UPDATE_INTERVAL:
		overview_update_timer = 0.0
		_update_overview()
	
	# 定时检查装备变化
	_equipment_update_timer += delta
	if _equipment_update_timer >= EQUIPMENT_UPDATE_INTERVAL:
		_equipment_update_timer = 0.0
		_check_equipment_list_changed()
	
	# 自动锁定
	if _auto_lock_enabled and player_ship and is_instance_valid(player_ship):
		_auto_lock_timer += delta
		if _auto_lock_timer >= AUTO_LOCK_INTERVAL:
			_auto_lock_timer = 0.0
			_process_auto_lock()
	
	# 自动攻击
	if _auto_attack_enabled and player_ship and is_instance_valid(player_ship):
		_auto_attack_timer += delta
		if _auto_attack_timer >= AUTO_ATTACK_INTERVAL:
			_auto_attack_timer = 0.0
			_process_auto_attack()

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
	
	# 先断开可能残留的旧连接，再重新连接（防止 repeat connect 错误）
	if target.shield_changed.is_connected(_update_target_shield):
		target.shield_changed.disconnect(_update_target_shield)
	if target.armor_changed.is_connected(_update_target_armor):
		target.armor_changed.disconnect(_update_target_armor)
	if target.hull_changed.is_connected(_update_target_hull):
		target.hull_changed.disconnect(_update_target_hull)
	if target.ship_destroyed.is_connected(_on_target_destroyed):
		target.ship_destroyed.disconnect(_on_target_destroyed)
	target.shield_changed.connect(_update_target_shield)
	target.armor_changed.connect(_update_target_armor)
	target.hull_changed.connect(_update_target_hull)
	target.ship_destroyed.connect(_on_target_destroyed)
	
	_update_target_shield(target.current_shield, target.max_shield)
	_update_target_armor(target.current_armor, target.max_armor)
	_update_target_hull(target.current_hull, target.max_hull)
	_update_lock_button_visibility()

func _update_target_distance() -> void:
	if not target_dist_label or not _target_node or not is_instance_valid(_target_node):
		return
	if not player_ship:
		return
	var dist = player_ship.global_position.distance_to(_target_node.global_position)
	target_dist_label.text = "距离: " + _format_distance(dist)

func _on_target_lost(target: Ship) -> void:
	# 断开当前目标面板的信号连接（防止 repeat connect 错误）
	if _target_node == target and is_instance_valid(target):
		if target.shield_changed.is_connected(_update_target_shield):
			target.shield_changed.disconnect(_update_target_shield)
		if target.armor_changed.is_connected(_update_target_armor):
			target.armor_changed.disconnect(_update_target_armor)
		if target.hull_changed.is_connected(_update_target_hull):
			target.hull_changed.disconnect(_update_target_hull)
		if target.ship_destroyed.is_connected(_on_target_destroyed):
			target.ship_destroyed.disconnect(_on_target_destroyed)
	
	if target_info_panel:
		target_info_panel.hide()
	_target_node = null
	_update_lock_button_visibility()
	# 目标解除锁定 → 停止所有攻击该目标的武器
	_clear_weapons_targeting(target)

func _on_target_destroyed() -> void:
	# 断开信号连接
	if _target_node and is_instance_valid(_target_node) and _target_node is Ship:
		var target = _target_node as Ship
		if target.shield_changed.is_connected(_update_target_shield):
			target.shield_changed.disconnect(_update_target_shield)
		if target.armor_changed.is_connected(_update_target_armor):
			target.armor_changed.disconnect(_update_target_armor)
		if target.hull_changed.is_connected(_update_target_hull):
			target.hull_changed.disconnect(_update_target_hull)
		if target.ship_destroyed.is_connected(_on_target_destroyed):
			target.ship_destroyed.disconnect(_on_target_destroyed)
	if target_info_panel:
		target_info_panel.hide()
	_target_node = null
	_update_lock_button_visibility()
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
		# Ctrl+左键 → 锁定目标（仅飞船，已锁定的不再重复操作）
		elif event.ctrl_pressed:
			var target_node = entry.get("node")
			if target_node is Ship and is_instance_valid(target_node) and target_node not in watched_targets:
				_add_watched_target(target_node)
				add_message("已锁定: " + entry_name(target_node), Color(0.3, 0.8, 1))
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
	
	_update_lock_button_visibility()

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
		player_ship.order_approach(_target_node)
		add_message("持续靠近: " + entry_name(_target_node), Color(0.3, 0.8, 1))

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

func _on_btn_attack() -> void:
	"""攻击按钮：若目标未锁定则先锁定，锁定后调用全部武器攻击"""
	if not player_ship or not _target_node or not is_instance_valid(_target_node):
		return
	if not (_target_node is Ship):
		add_message("只能攻击飞船目标!", Color(1, 0.6, 0.3))
		return
	
	var target_ship = _target_node as Ship
	
	# 如果目标未锁定，先锁定
	if target_ship not in watched_targets:
		player_ship.lock_target(target_ship)
		_add_watched_target(target_ship)
		add_message("已锁定: " + entry_name(target_ship), Color(0.3, 0.8, 1))
		# 短暂等待一帧让锁定生效
		await get_tree().process_frame
	
	# 设为当前活跃目标
	player_ship.set_active_target(target_ship)
	
	# 调用全部武器攻击此目标
	var weapon_count = 0
	for w in player_ship.weapon_nodes:
		if w is Weapon:
			w.assign_target(target_ship)
			weapon_count += 1
	
	add_message("全部武器攻击: " + entry_name(target_ship), Color(1, 0.3, 0.3))

## ====== 锁定目标面板 ======

## 锁定按钮点击
func _on_btn_lock_pressed() -> void:
	if not _target_node or not is_instance_valid(_target_node):
		return
	if not (_target_node is Ship):
		return
	var target_ship = _target_node as Ship
	if target_ship in watched_targets:
		return
	_add_watched_target(target_ship)
	add_message("已锁定: " + entry_name(target_ship), Color(0.3, 0.8, 1))

## 解除锁定按钮点击
func _on_btn_unlock_pressed() -> void:
	if not _target_node or not is_instance_valid(_target_node):
		return
	if not (_target_node is Ship):
		return
	var target_ship = _target_node as Ship
	if target_ship not in watched_targets:
		return
	_remove_watched_target(target_ship)
	add_message("取消锁定: " + entry_name(target_ship), Color(0.7, 0.7, 0.7))

## 根据当前目标是否已锁定，切换锁定/解除锁定按钮显示
func _update_lock_button_visibility() -> void:
	if not btn_lock or not btn_unlock:
		return
	if not _target_node or not is_instance_valid(_target_node) or not (_target_node is Ship):
		btn_lock.hide()
		btn_unlock.hide()
		return
	
	var is_watched = _target_node in watched_targets
	btn_lock.visible = not is_watched
	btn_unlock.visible = is_watched

## 添加目标到锁定面板
func _add_watched_target(target: Ship) -> void:
	if target in watched_targets:
		return
	if not locked_panel or not locked_list:
		return
	
	watched_targets.append(target)
	
	# 同步注册到飞船的锁定列表，确保自动攻击等机制能识别该目标
	if player_ship and is_instance_valid(player_ship):
		player_ship.lock_target(target)
	
	# 实例化卡片场景
	var card = LOCKED_CARD_SCENE.instantiate() as LockedTargetCard
	locked_list.add_child(card)
	locked_list.move_child(card, 0)  # 新卡片插入最左侧，从右往左排列
	card.setup(target)  # 在 _ready 之后调用，@onready 节点已就绪
	
	# 创建绑定的信号回调并存储以便断开
	var health_cb = _update_watched_target_health.bind(target)
	var destroy_cb = _on_watched_target_destroyed.bind(target)
	
	card.card_clicked.connect(_select_locked_target)
	
	_watched_target_data[target] = {
		"card": card,
		"health_sig": health_cb,
		"destroy_sig": destroy_cb
	}
	
	# 先断开可能残留的旧连接（防止 repeat connect 错误）
	if target.shield_changed.is_connected(health_cb):
		target.shield_changed.disconnect(health_cb)
	if target.hull_changed.is_connected(health_cb):
		target.hull_changed.disconnect(health_cb)
	if target.armor_changed.is_connected(health_cb):
		target.armor_changed.disconnect(health_cb)
	if target.capacitor_changed.is_connected(health_cb):
		target.capacitor_changed.disconnect(health_cb)
	target.shield_changed.connect(health_cb)
	target.hull_changed.connect(health_cb)
	target.armor_changed.connect(health_cb)
	target.capacitor_changed.connect(health_cb)
	target.ship_destroyed.connect(destroy_cb, CONNECT_ONE_SHOT)
	
	locked_panel.show()
	_update_lock_button_visibility()

## 从锁定面板移除目标
func _remove_watched_target(target: Ship) -> void:
	watched_targets.erase(target)
	
	var data = _watched_target_data.get(target)
	if data:
		var card = data["card"] as Control
		if card and is_instance_valid(card):
			card.queue_free()
		
		# 使用存储的回调断开信号
		if target.shield_changed.is_connected(data["health_sig"]):
			target.shield_changed.disconnect(data["health_sig"])
		if target.hull_changed.is_connected(data["health_sig"]):
			target.hull_changed.disconnect(data["health_sig"])
		if target.armor_changed.is_connected(data["health_sig"]):
			target.armor_changed.disconnect(data["health_sig"])
		if target.capacitor_changed.is_connected(data["health_sig"]):
			target.capacitor_changed.disconnect(data["health_sig"])
		if target.ship_destroyed.is_connected(data["destroy_sig"]):
			target.ship_destroyed.disconnect(data["destroy_sig"])
	
	# 如果被移除的是当前选中目标，清除选中状态
	if _selected_locked_target == target:
		_selected_locked_target = null
	
	_watched_target_data.erase(target)
	
	# 目标解除锁定 → 从飞船锁定列表移除并停止所有攻击该目标的武器
	if player_ship and is_instance_valid(player_ship):
		player_ship.unlock_target(target)
	_clear_weapons_targeting(target)
	
	# 如果锁定面板为空则隐藏
	if locked_panel and watched_targets.size() == 0:
		locked_panel.hide()
		_selected_locked_target = null
	
	_update_lock_button_visibility()

## 锁定目标被摧毁时自动移除
func _on_watched_target_destroyed(target: Ship) -> void:
	_remove_watched_target(target)
	add_message("锁定目标已摧毁: " + entry_name(target), Color.RED)

## 选中锁定面板中的目标（高亮卡片、更新目标面板）
func _select_locked_target(target: Ship) -> void:
	if not is_instance_valid(target):
		return
	# 取消旧选中
	if _selected_locked_target and _selected_locked_target != target:
		_update_card_selection_style(_selected_locked_target, false)
	
	_selected_locked_target = target
	_update_card_selection_style(target, true)
	
	# 显示目标信息
	_show_target_info(target)
	
	# 如果玩家飞船能锁定此目标，设为 active_target
	if player_ship and target in player_ship.locked_targets:
		player_ship.set_active_target(target)

## 更新卡片的选中高亮样式
func _update_card_selection_style(target: Ship, selected: bool) -> void:
	var data = _watched_target_data.get(target)
	if not data:
		return
	var card = data["card"] as LockedTargetCard
	if not card or not is_instance_valid(card):
		return
	card.set_selected(selected)

## 更新锁定面板中目标的四条状态条（护盾/装甲/结构/电容）
func _update_watched_target_health(_current: float, _max_value: float, target: Ship) -> void:
	var data = _watched_target_data.get(target)
	if not data:
		return
	var card = data["card"] as LockedTargetCard
	if not card or not is_instance_valid(card):
		return
	card.update_bars(target)

const LOCKED_CARD_SCENE = preload("res://scenes/ui/LockedTargetCard.tscn")
const EQUIPMENT_CARD_SCENE = preload("res://scenes/ui/WeaponCard.tscn")

## ====== 装备面板 ======

## 收集所有装备（武器+模块）
func _collect_equipment() -> Array[Node]:
	var result: Array[Node] = []
	if not player_ship or not is_instance_valid(player_ship):
		return result
	
	# 武器
	for w in player_ship.weapon_nodes:
		if w is Weapon:
			result.append(w)
	
	# 低槽模块（维修装备等）
	for m in player_ship.low_slot_modules:
		if m is ShipModule:
			result.append(m)
	
	return result

## 刷新装备面板
func _refresh_equipment_panel() -> void:
	if not equipment_list or not player_ship:
		return
	
	# 清空旧卡片
	for card in _equipment_cards:
		if is_instance_valid(card):
			card.queue_free()
	_equipment_cards.clear()
	
	var all_equip = _collect_equipment()
	
	# 为每个装备创建卡片
	for equip in all_equip:
		var card = EQUIPMENT_CARD_SCENE.instantiate() as EquipmentCard
		equipment_list.add_child(card)
		
		if equip is Weapon:
			card.setup_weapon(equip as Weapon)
		elif equip is ShipModule:
			card.setup_module(equip as ShipModule)
		
		card.card_clicked.connect(_on_equipment_card_clicked)
		_equipment_cards.append(card)
	
	# 有装备时显示面板
	if equipment_panel:
		equipment_panel.visible = _equipment_cards.size() > 0

## 检查装备列表是否有变化
func _check_equipment_list_changed() -> void:
	if not player_ship or not is_instance_valid(player_ship):
		return
	
	var current_count = _equipment_cards.size()
	var actual_count = _collect_equipment().size()
	
	if current_count != actual_count:
		_refresh_equipment_panel()

## 装备卡片点击
func _on_equipment_card_clicked(node: Node) -> void:
	if not node or not is_instance_valid(node):
		return
	
	if node is Weapon:
		_on_weapon_clicked(node as Weapon)
	elif node is ShipModule:
		_on_module_clicked(node as ShipModule)

## 武器点击：分配/取消目标
func _on_weapon_clicked(weapon: Weapon) -> void:
	var target = _selected_locked_target
	if not target or not is_instance_valid(target) or not target.is_alive:
		add_message("请先在锁定面板中选择目标", Color(0.7, 0.7, 0.7))
		return
	
	if weapon.assigned_target == target:
		weapon.clear_target()
		add_message("武器「%s」停止攻击" % weapon.weapon_data.weapon_name, Color(0.7, 0.7, 0.7))
	else:
		weapon.assign_target(target)
		add_message("武器「%s」攻击 %s" % [weapon.weapon_data.weapon_name, _tname(target)], Color(1, 0.5, 0.2))

## 模块点击：启动/停止循环
func _on_module_clicked(mod: ShipModule) -> void:
	if mod.is_active:
		mod.deactivate()
		add_message("装备「%s」已停止" % mod.module_data.module_name, Color(0.7, 0.7, 0.7))
	else:
		mod.activate()
		add_message("装备「%s」已启动" % mod.module_data.module_name, Color(0.3, 1, 0.3))

## 键盘快捷键 1-8 → 触发对应装备卡片点击
func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	
	var key_index = -1
	match event.keycode:
		KEY_1: key_index = 0
		KEY_2: key_index = 1
		KEY_3: key_index = 2
		KEY_4: key_index = 3
		KEY_5: key_index = 4
		KEY_6: key_index = 5
		KEY_7: key_index = 6
		KEY_8: key_index = 7
	
	if key_index >= 0 and key_index < _equipment_cards.size():
		var card = _equipment_cards[key_index]
		if card and is_instance_valid(card) and card.bound_node:
			_on_equipment_card_clicked(card.bound_node)

## 辅助：获取目标显示名称
static func _tname(node: Node) -> String:
	if node is Ship and node.ship_data:
		return node.ship_data.ship_name
	return "目标"

## ====== 自动锁定/攻击 ======

func _on_auto_lock_toggled(button_pressed: bool) -> void:
	_auto_lock_enabled = button_pressed
	if button_pressed:
		add_message("自动锁定: 开启", Color(0.3, 0.8, 1))
	else:
		add_message("自动锁定: 关闭", Color(0.7, 0.7, 0.7))
	_save_panel_layout()

func _on_auto_attack_toggled(button_pressed: bool) -> void:
	_auto_attack_enabled = button_pressed
	if button_pressed:
		add_message("自动攻击: 开启", Color(1, 0.3, 0.3))
	else:
		# 关闭时清除所有武器的目标分配
		_clear_all_weapon_assignments()
		add_message("自动攻击: 关闭", Color(0.7, 0.7, 0.7))
	_save_panel_layout()

## 自动锁定：扫描附近敌对飞船并锁定
func _process_auto_lock() -> void:
	if not player_ship or not is_instance_valid(player_ship):
		return
	
	var max_locks = player_ship.max_locked_targets
	if player_ship.locked_targets.size() >= max_locks:
		return
	
	# 扫描场景中的敌对飞船
	var root = get_tree().current_scene
	if not root:
		return
	
	var hostiles: Array[Ship] = []
	_find_hostile_ships(root, hostiles, player_ship.global_position)
	
	# 排序：按距离由近到远
	hostiles.sort_custom(func(a: Ship, b: Ship): 
		var da = player_ship.global_position.distance_squared_to(a.global_position)
		var db = player_ship.global_position.distance_squared_to(b.global_position)
		return da < db
	)
	
	for ship in hostiles:
		if player_ship.locked_targets.size() >= max_locks:
			break
		if ship not in player_ship.locked_targets and ship.is_alive:
			player_ship.lock_target(ship)
			# 自动添加到锁定面板
			if ship not in watched_targets:
				_add_watched_target(ship)

## 自动攻击：将武器分配给锁定的敌对目标
func _process_auto_attack() -> void:
	if not player_ship or not is_instance_valid(player_ship):
		return
	
	# 获取所有锁定的敌对目标
	var hostile_targets: Array[Ship] = []
	for t in player_ship.locked_targets:
		if t and is_instance_valid(t) and t.is_alive and t.faction == Ship.Faction.NPC_HOSTILE:
			hostile_targets.append(t)
	
	# 检查武器是否仍在攻击有效目标，若目标已解锁/摧毁则清除分配
	for w in player_ship.weapon_nodes:
		if w is Weapon and w.assigned_target:
			if w.assigned_target not in hostile_targets:
				w.clear_target()
	
	# 无有效锁定目标 → 所有武器停止攻击
	if hostile_targets.is_empty():
		return
	
	# 为没有分配目标（或目标已清除）的武器分配第一个锁定目标
	var primary_target = hostile_targets[0]
	if not primary_target or not primary_target.is_alive:
		return
	
	for w in player_ship.weapon_nodes:
		if w is Weapon and w.assigned_target == null:
			w.assign_target(primary_target)

## 清除所有武器的目标分配
func _clear_all_weapon_assignments() -> void:
	if not player_ship or not is_instance_valid(player_ship):
		return
	for w in player_ship.weapon_nodes:
		if w is Weapon:
			w.clear_target()

## 清除攻击指定目标的武器分配
func _clear_weapons_targeting(target: Ship) -> void:
	if not player_ship or not is_instance_valid(player_ship):
		return
	for w in player_ship.weapon_nodes:
		if w is Weapon and w.assigned_target == target:
			w.clear_target()

## 递归查找敌对飞船
func _find_hostile_ships(node: Node, result: Array[Ship], player_pos: Vector3) -> void:
	for child in node.get_children():
		if child is Ship and child.faction == Ship.Faction.NPC_HOSTILE and child.is_alive:
			var dist = player_pos.distance_to(child.global_position)
			if dist <= player_ship.current_targeting_range:
				result.append(child)
		_find_hostile_ships(child, result, player_pos)

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

## ====== 新建游戏 ======

func _on_new_game_pressed() -> void:
	# 删除存档文件
	_delete_save_files()
	
	# 重置全局玩家数据
	if global_ref:
		global_ref.init_player_data()
	
	# 重新加载主场景
	get_tree().reload_current_scene()

func _on_restart_game_pressed() -> void:
	# 直接重新加载主场景，不重置数据
	get_tree().reload_current_scene()

func _delete_save_files() -> void:
	# 删除面板布局存档（含自动锁定/攻击设置）
	if FileAccess.file_exists(PANEL_SAVE_PATH):
		DirAccess.remove_absolute(PANEL_SAVE_PATH)

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
	var locked = get_node_or_null("LockedPanel")
	var weapon = get_node_or_null("EquipmentPanel")
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
	if locked:
		cfg.set_value("LockedPanel", "offset_left", locked.offset_left)
		cfg.set_value("LockedPanel", "offset_top", locked.offset_top)
		cfg.set_value("LockedPanel", "offset_right", locked.offset_right)
		cfg.set_value("LockedPanel", "offset_bottom", locked.offset_bottom)
	if weapon:
		cfg.set_value("EquipmentPanel", "offset_left", weapon.offset_left)
		cfg.set_value("EquipmentPanel", "offset_top", weapon.offset_top)
		cfg.set_value("EquipmentPanel", "offset_right", weapon.offset_right)
		cfg.set_value("EquipmentPanel", "offset_bottom", weapon.offset_bottom)
	var msg_log = get_node_or_null("MessageLog")
	if msg_log:
		cfg.set_value("MessageLog", "offset_left", msg_log.offset_left)
		cfg.set_value("MessageLog", "offset_top", msg_log.offset_top)
		cfg.set_value("MessageLog", "offset_right", msg_log.offset_right)
		cfg.set_value("MessageLog", "offset_bottom", msg_log.offset_bottom)
	# 保存自动锁定/攻击勾选状态
	if auto_lock_check:
		cfg.set_value("AutoSettings", "auto_lock", auto_lock_check.button_pressed)
	if auto_attack_check:
		cfg.set_value("AutoSettings", "auto_attack", auto_attack_check.button_pressed)
	cfg.save(PANEL_SAVE_PATH)

func _load_panel_layout() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(PANEL_SAVE_PATH) != OK:
		# 没有存档：自动锁定/攻击默认开启
		_auto_lock_enabled = true
		_auto_attack_enabled = true
		if auto_lock_check:
			auto_lock_check.set_pressed_no_signal(true)
		if auto_attack_check:
			auto_attack_check.set_pressed_no_signal(true)
		return
	var overview = get_node_or_null("OverviewPanel")
	var target = get_node_or_null("TargetPanel")
	var ship_status = get_node_or_null("ShipStatusPanel")
	var locked = get_node_or_null("LockedPanel")
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
	if locked:
		if cfg.has_section_key("LockedPanel", "offset_left"):
			locked.offset_left = cfg.get_value("LockedPanel", "offset_left")
			locked.offset_top = cfg.get_value("LockedPanel", "offset_top")
			locked.offset_right = cfg.get_value("LockedPanel", "offset_right")
			locked.offset_bottom = cfg.get_value("LockedPanel", "offset_bottom")
	var weapon = get_node_or_null("EquipmentPanel")
	if weapon:
		if cfg.has_section_key("EquipmentPanel", "offset_left"):
			weapon.offset_left = cfg.get_value("EquipmentPanel", "offset_left")
			weapon.offset_top = cfg.get_value("EquipmentPanel", "offset_top")
			weapon.offset_right = cfg.get_value("EquipmentPanel", "offset_right")
			weapon.offset_bottom = cfg.get_value("EquipmentPanel", "offset_bottom")
	var msg_log = get_node_or_null("MessageLog")
	if msg_log:
		if cfg.has_section_key("MessageLog", "offset_left"):
			msg_log.offset_left = cfg.get_value("MessageLog", "offset_left")
			msg_log.offset_top = cfg.get_value("MessageLog", "offset_top")
			msg_log.offset_right = cfg.get_value("MessageLog", "offset_right")
			msg_log.offset_bottom = cfg.get_value("MessageLog", "offset_bottom")
	
	# 加载自动锁定/攻击勾选状态
	if cfg.has_section_key("AutoSettings", "auto_lock"):
		var val = cfg.get_value("AutoSettings", "auto_lock", false)
		_auto_lock_enabled = val
		if auto_lock_check:
			auto_lock_check.set_pressed_no_signal(val)
	if cfg.has_section_key("AutoSettings", "auto_attack"):
		var val = cfg.get_value("AutoSettings", "auto_attack", false)
		_auto_attack_enabled = val
		if auto_attack_check:
			auto_attack_check.set_pressed_no_signal(val)

## ====== 消息与信息 ======

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
