extends DraggablePanel
class_name FleetPanel

## 舰队面板 - 显示和管理玩家舰队
## 位于屏幕左侧，显示所有舰队及其成员飞船
## 继承 DraggablePanel 获得拖拽移动和边缘拉伸功能

const AllyAI = preload("res://scripts/fleet/AllyAIController.gd")

const SHIP_ICONS := {
	ShipData.ShipClass.FRIGATE: preload("res://images/icon_frigate.png"),
	ShipData.ShipClass.CRUISER: preload("res://images/icon_cruiser.png"),
	ShipData.ShipClass.BATTLESHIP: preload("res://images/icon_battleship.png"),
}

## 节点引用
var _scroll: ScrollContainer = null
var _list: VBoxContainer = null
var _btn_add: Button = null
var _btn_delete: Button = null
var _btn_rename: Button = null
var _btn_summon: Button = null

## 舰队行节点缓存 {fleet_id: Panel}
var _fleet_rows: Dictionary = {}
## 飞船行节点缓存 {ship: Panel}
var _ship_rows: Dictionary = {}
## 选中舰队的ID
var _selected_fleet_id: int = -1
## 更新定时器
var _update_timer: float = 0.0
const UPDATE_INTERVAL: float = 1.0

func _ready() -> void:
	# 调用父类 DraggablePanel._ready() 以启用拖拽和拉伸
	super._ready()
	
	# 查找子节点
	_header = get_node_or_null("HeaderBg") as Panel
	_scroll = get_node_or_null("ScrollContainer") as ScrollContainer
	_list = get_node_or_null("ScrollContainer/FleetList") as VBoxContainer
	_btn_add = get_node_or_null("ButtonBar/BtnAddFleet") as Button
	_btn_delete = get_node_or_null("ButtonBar/BtnDeleteFleet") as Button
	_btn_rename = get_node_or_null("ButtonBar/BtnRenameFleet") as Button
	_btn_summon = get_node_or_null("ButtonBar/BtnSummonAlly") as Button
	
	# 连接按钮
	if _btn_add:
		_btn_add.pressed.connect(_on_add_fleet)
	if _btn_delete:
		_btn_delete.pressed.connect(_on_delete_fleet)
	if _btn_rename:
		_btn_rename.pressed.connect(_on_rename_fleet)
	if _btn_summon:
		_btn_summon.pressed.connect(_on_summon_ally)
	
	# 连接 FleetManager 信号
	var fm = get_node_or_null("/root/FleetManager")
	if fm:
		fm.fleet_created.connect(_refresh)
		fm.fleet_deleted.connect(_refresh)
		fm.fleet_renamed.connect(_refresh)
		fm.ship_added_to_fleet.connect(_refresh)
		fm.ship_removed_from_fleet.connect(_refresh)
		fm.player_ship_registered.connect(_refresh)
		fm.player_ship_unregistered.connect(_refresh)
	
	_refresh()

func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer >= UPDATE_INTERVAL:
		_update_timer = 0.0
		_refresh()

## 刷新舰队列表
func _refresh(_unused = null) -> void:
	if not _list:
		return
	_fleet_rows.clear()
	_ship_rows.clear()
	
	# 清空列表
	for child in _list.get_children():
		child.queue_free()
	
	var fm = get_node_or_null("/root/FleetManager")
	if not fm:
		return
	
	fm.cleanup_all()
	
	# 显示舰队
	for fleet in fm.fleets:
		_add_fleet_row(fleet)
	
	# 显示未加入舰队的飞船
	var unassigned = fm.get_ships_without_fleet()
	if unassigned.size() > 0:
		_add_separator("未编队飞船")
		for ship in unassigned:
			_add_ship_row(ship, -1)

## 添加分隔标签
func _add_separator(text: String) -> void:
	var sep = Label.new()
	sep.text = text
	sep.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5, 1))
	sep.add_theme_font_size_override("font_size", 9)
	sep.custom_minimum_size = Vector2(0, 16)
	_list.add_child(sep)

## 添加舰队行
func _add_fleet_row(fleet: Fleet) -> void:
	var row = Panel.new()
	row.custom_minimum_size = Vector2(0, 22)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.custom_minimum_size = Vector2(0, 22)
	row.add_child(hbox)
	
	# 展开/折叠按钮
	var expand_btn = Button.new()
	expand_btn.text = "▼"
	expand_btn.flat = true
	expand_btn.custom_minimum_size = Vector2(18, 22)
	expand_btn.add_theme_font_size_override("font_size", 8)
	expand_btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7, 1))
	expand_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	hbox.add_child(expand_btn)
	
	# 舰队名称标签
	var name_label = Label.new()
	name_label.text = "%s (%d)" % [fleet.fleet_name, fleet.ship_count()]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color(0.3, 0.6, 1, 1))
	name_label.mouse_filter = Control.MOUSE_FILTER_STOP
	hbox.add_child(name_label)
	
	_list.add_child(row)
	_fleet_rows[fleet.fleet_id] = row
	
	# 点击舰队行 → 选中
	name_label.gui_input.connect(_on_fleet_label_input.bind(fleet.fleet_id, name_label, row))
	expand_btn.pressed.connect(_on_fleet_expand.bind(fleet.fleet_id, expand_btn))
	
	# 默认展开显示飞船
	_on_fleet_expand(fleet.fleet_id, expand_btn)

## 展开/折叠舰队
func _on_fleet_expand(fleet_id: int, btn: Button) -> void:
	var expanded = btn.text == "▼"
	btn.text = "▲" if expanded else "▼"
	
	# 移除旧的飞船行（如果有的话）
	_remove_fleet_ship_rows(fleet_id)
	
	if expanded:
		_add_fleet_ship_rows(fleet_id)

## 移除舰队的飞船行
func _remove_fleet_ship_rows(fleet_id: int) -> void:
	var fm = get_node_or_null("/root/FleetManager")
	if not fm:
		return
	var fleet = fm.get_fleet_by_id(fleet_id)
	if not fleet:
		return
	
	# 获取该舰队行在列表中的索引
	var fleet_row = _fleet_rows.get(fleet_id)
	if not fleet_row:
		return
	
	var idx = 0
	for child in _list.get_children():
		if child == fleet_row:
			break
		idx += 1
	
	# 删除该舰队后面的飞船行（直到下一个舰队或无舰队分隔）
	var to_remove: Array = []
	var next_idx = idx + 1
	while next_idx < _list.get_child_count():
		var child = _list.get_child(next_idx)
		if child is Panel and child.custom_minimum_size.y <= 22:
			# 可能是飞船行或另一个舰队行
			if _is_ship_row(child):
				to_remove.append(child)
				next_idx += 1
			else:
				break
		else:
			break
	
	for child in to_remove:
		_list.remove_child(child)
		child.queue_free()

## 判断是否是飞船行
func _is_ship_row(panel: Panel) -> bool:
	return panel.has_meta("ship_node")

## 添加舰队的飞船行
func _add_fleet_ship_rows(fleet_id: int) -> void:
	var fm = get_node_or_null("/root/FleetManager")
	if not fm:
		return
	var fleet = fm.get_fleet_by_id(fleet_id)
	if not fleet:
		return
	
	var ships = fleet.get_valid_ships()
	var fleet_row = _fleet_rows.get(fleet_id)
	if not fleet_row:
		return
	
	# 找到舰队行在列表中的位置
	var insert_idx = 0
	for i in range(_list.get_child_count()):
		if _list.get_child(i) == fleet_row:
			insert_idx = i + 1
			break
	
	for ship in ships:
		var ship_row = _create_ship_row(ship, fleet_id)
		_list.add_child(ship_row)
		_list.move_child(ship_row, insert_idx)
		insert_idx += 1

## 创建飞船行
func _create_ship_row(ship: Node, fleet_id: int) -> Panel:
	var row = Panel.new()
	row.custom_minimum_size = Vector2(0, 20)
	row.mouse_filter = Control.MOUSE_FILTER_STOP  # STOP 防止事件穿透到3D场景
	row.set_meta("ship_node", ship)
	
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.custom_minimum_size = Vector2(0, 20)
	row.add_child(hbox)
	
	# 图标
	var icon = TextureRect.new()
	icon.custom_minimum_size = Vector2(16, 16)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if ship is Ship and ship.ship_data:
		var icon_tex = SHIP_ICONS.get(ship.ship_data.ship_class)
		if icon_tex:
			icon.texture = icon_tex
	hbox.add_child(icon)
	
	# 飞船名称
	var name_label = Label.new()
	if ship is Ship and ship.ship_data:
		name_label.text = ship.ship_data.ship_name
	else:
		name_label.text = ship.name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 9)
	name_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8, 1))
	hbox.add_child(name_label)
	
	# 拖拽支持
	row.gui_input.connect(_on_ship_row_input.bind(row, ship, fleet_id))
	
	return row

## 添加未编队飞船行
func _add_ship_row(ship: Node, fleet_id: int) -> void:
	var row = _create_ship_row(ship, fleet_id)
	_list.add_child(row)

## 点击舰队标签 → 选中
func _on_fleet_label_input(event: InputEvent, fleet_id: int, label: Label, row: Panel) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_fleet(fleet_id)
		# 高亮选中的舰队行
		_update_selection_highlight()

## 选中舰队
func _select_fleet(fleet_id: int) -> void:
	_selected_fleet_id = fleet_id
	for fid in _fleet_rows:
		if _fleet_rows[fid] and is_instance_valid(_fleet_rows[fid]):
			var children = _fleet_rows[fid].get_children()
			for child in children:
				if child is HBoxContainer:
					for c in child.get_children():
						if c is Label:
							if fid == fleet_id:
								c.add_theme_color_override("font_color", Color(0.6, 1, 1, 1))
							else:
								c.add_theme_color_override("font_color", Color(0.3, 0.6, 1, 1))

## 拖拽状态（实例变量）
var _drag_active: bool = false
var _drag_ship: Node = null
var _drag_source_fleet: int = -1
## 拖拽追踪（在 _input 中检测，无需依赖 gui_input 的事件顺序）
var _press_pos: Vector2 = Vector2.ZERO
var _press_ship: Node = null
var _press_fleet: int = -1
var _press_active: bool = false
## 静态标记 - 供 PlayerController 等外部脚本检查是否有 UI 拖拽正在进行
static var global_drag_active: bool = false

func _input(event: InputEvent) -> void:
	# 拖拽进行中时，拦截所有输入事件，防止穿透到3D场景
	if _drag_active:
		if event is InputEventMouseButton or event is InputEventMouseMotion:
			get_viewport().set_input_as_handled()
			if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_finish_drag()
		return  # 已激活拖拽时不再走下面的检测
	
	# 鼠标按下 → 记录，检查是否点在飞船行上
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_press_pos = get_viewport().get_mouse_position()
		_press_ship = _find_ship_at_position(_press_pos)
		_press_fleet = _find_fleet_at_position(_press_pos)
		_press_active = true
		# 立即设置全局拖拽标记，防止 PlayerController 在这一帧开始镜头旋转
		if _press_ship != null:
			global_drag_active = true
		return
	
	# 鼠标释放 → 清除全局标记
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		global_drag_active = false
		_press_active = false
		_press_ship = null
		return
	
	# 鼠标左键拖动 → 检测是否从飞船行开始，超过阈值则激活拖拽
	if event is InputEventMouseMotion and event.button_mask == MOUSE_BUTTON_MASK_LEFT:
		if not _press_active or _press_ship == null:
			return
		var drag_dist = get_viewport().get_mouse_position().distance_to(_press_pos)
		if drag_dist < 10.0:
			return
		
		# 激活手动拖拽 — 在 _input 中设置，先于 PlayerController 的 _input 处理
		_drag_active = true
		global_drag_active = true
		_drag_ship = _press_ship
		_drag_source_fleet = _press_fleet
		get_viewport().set_input_as_handled()
		_press_active = false

## 根据全局坐标查找该位置是否有飞船行，返回飞船节点
func _find_ship_at_position(pos: Vector2) -> Node:
	# 遍历所有 _fleet_rows 展开后的飞船行
	# 直接检查 _list 中的子节点
	if not _list or not _list.is_inside_tree():
		return null
	for child in _list.get_children():
		if not (child is Panel) or not _is_ship_row(child):
			continue
		var global_rect = Rect2()
		if child is Panel:
			global_rect = child.get_global_rect()
			if global_rect.has_point(pos):
				return child.get_meta("ship_node", null)
	return null

func _update_selection_highlight() -> void:
	for fid in _fleet_rows:
		if _fleet_rows[fid] and is_instance_valid(_fleet_rows[fid]):
			var bg_color = Color(1, 1, 1, 0.12) if fid == _selected_fleet_id else Color(0, 0, 0, 0)
			var style = StyleBoxFlat.new()
			style.bg_color = bg_color
			_fleet_rows[fid].add_theme_stylebox_override("panel", style)

## 飞船行输入事件（仅处理单击选中，拖拽由 _input 统一处理）
func _on_ship_row_input(event: InputEvent, row: Panel, ship: Node, fleet_id: int) -> void:
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 如果没有激活拖拽，视为点击 → 选中该舰队
		if not _drag_active and fleet_id >= 0:
			_select_fleet(fleet_id)
			_update_selection_highlight()

## 结束拖拽 → 处理落点
func _finish_drag() -> void:
	if not _drag_active or not _drag_ship or not is_instance_valid(_drag_ship):
		_drag_active = false
		global_drag_active = false
		_drag_ship = null
		return
	
	var fm = get_node_or_null("/root/FleetManager")
	if fm:
		var global_pos = get_viewport().get_mouse_position()
		var target_fleet_id = _find_fleet_at_position(global_pos)
		
		if target_fleet_id >= 0:
			if target_fleet_id != _drag_source_fleet:
				fm.add_ship_to_fleet(_drag_ship, target_fleet_id)
				var fleet = fm.get_fleet_by_id(target_fleet_id)
				if fleet:
					var hud = get_node_or_null("/root/SpaceWar/HUD")
					if hud and hud.has_method("add_message"):
						hud.add_message("%s 加入 %s" % [
							_drag_ship.ship_data.ship_name if _drag_ship is Ship and _drag_ship.ship_data else _drag_ship.name,
							fleet.fleet_name
						], Color(0.3, 0.8, 1))
		elif target_fleet_id == -2:
			# 拖到未编队区域
			fm.remove_ship_from_fleet(_drag_ship)
			var hud = get_node_or_null("/root/SpaceWar/HUD")
			if hud and hud.has_method("add_message"):
				hud.add_message("%s 已脱离编队" % (
					_drag_ship.ship_data.ship_name if _drag_ship is Ship and _drag_ship.ship_data else _drag_ship.name
				), Color(0.7, 0.7, 0.7))
		
		_refresh()
	
	_drag_active = false
	global_drag_active = false
	_drag_ship = null
	_drag_source_fleet = -1

## 查找位置处的舰队ID（pos 为全局屏幕坐标）
func _find_fleet_at_position(pos: Vector2) -> int:
	# 遍历所有舰队行，检查鼠标是否在某行的全局范围内
	for fid in _fleet_rows:
		var row = _fleet_rows[fid]
		if not row or not is_instance_valid(row) or not row.is_inside_tree():
			continue
		# 计算该行的全局矩形
		var row_global_pos = row.get_global_rect().position
		var row_rect = Rect2(row_global_pos, row.size)
		# 稍微扩大点击区域便于操作
		row_rect = row_rect.grow(4.0)
		if row_rect.has_point(pos):
			return fid
	
	# 检查是否在ScrollContainer内（视为未编队区域）
	if _scroll and _scroll.is_inside_tree():
		var scroll_rect = Rect2(_scroll.global_position, _scroll.size)
		if scroll_rect.has_point(pos):
			return -2
	
	return -1

## ==================== 按钮操作 ====================

## 新建舰队
func _on_add_fleet() -> void:
	var fm = get_node_or_null("/root/FleetManager")
	if not fm:
		return
	
	# 默认舰队名
	var fleet_num = fm.fleets.size() + 1
	var fleet = fm.create_fleet("第%d舰队" % fleet_num)
	_selected_fleet_id = fleet.fleet_id
	_refresh()
	
	# 自动弹出重命名
	_on_rename_fleet()

## 删除舰队
func _on_delete_fleet() -> void:
	if _selected_fleet_id < 0:
		return
	var fm = get_node_or_null("/root/FleetManager")
	if not fm:
		return
	fm.delete_fleet(_selected_fleet_id)
	_selected_fleet_id = -1
	_refresh()

## 重命名舰队
func _on_rename_fleet() -> void:
	if _selected_fleet_id < 0:
		return
	var fm = get_node_or_null("/root/FleetManager")
	if not fm:
		return
	var fleet = fm.get_fleet_by_id(_selected_fleet_id)
	if not fleet:
		return
	
	# 使用输入对话框
	var dialog = AcceptDialog.new()
	# 使用 LineEdit 自定义对话框太复杂，直接用 InputDialog
	var line_edit = LineEdit.new()
	line_edit.text = fleet.fleet_name
	line_edit.placeholder_text = "输入舰队名称"
	line_edit.custom_minimum_size = Vector2(200, 30)
	
	var popup = PopupPanel.new()
	popup.title = "重命名舰队"
	var vbox = VBoxContainer.new()
	var label = Label.new()
	label.text = "请输入新名称："
	vbox.add_child(label)
	vbox.add_child(line_edit)
	var btn_box = HBoxContainer.new()
	var ok_btn = Button.new()
	ok_btn.text = "确定"
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	btn_box.add_child(ok_btn)
	btn_box.add_child(cancel_btn)
	vbox.add_child(btn_box)
	popup.add_child(vbox)
	
	add_child(popup)
	popup.popup_centered(Vector2(250, 150))
	
	ok_btn.pressed.connect(func():
		var new_name = line_edit.text.strip_edges()
		if not new_name.is_empty():
			fm.rename_fleet(_selected_fleet_id, new_name)
			_refresh()
		popup.queue_free()
	)
	cancel_btn.pressed.connect(func():
		popup.queue_free()
	)

## 召唤友军
func _on_summon_ally() -> void:
	var fm = get_node_or_null("/root/FleetManager")
	if not fm:
		return
	
	var player_ships = fm.get_all_player_ships()
	if player_ships.is_empty():
		return
	
	var leader = player_ships[0]
	
	# 随机选择船型
	var cls_idx = randi() % 3
	var ship_class: ShipData.ShipClass
	match cls_idx:
		0: ship_class = ShipData.ShipClass.FRIGATE
		1: ship_class = ShipData.ShipClass.CRUISER
		_: ship_class = ShipData.ShipClass.BATTLESHIP
	
	# 获取主场景的 Main 脚本
	var main = get_node_or_null("/root/SpaceWar")
	if not main or not main.has_method("_spawn_ally_ship"):
		# 手动生成
		_spawn_ally_ship_direct(ship_class, leader)
	else:
		# 使用 Main 的方法生成，然后注册
		var scene = Global.get_player_ship_scene(ship_class)
		var ship = scene.instantiate()
		
		ship.ship_data = ShipData.get_preset(ship_class)
		ship.ship_data.ship_name = Ship.generate_random_name(ship_class)
		ship.faction = Ship.Faction.PLAYER
		ship.faction_name = FleetManager.PLAYER_FACTION_NAME
		
		# 添加友军AI
		var ai = AllyAI.new()
		ai.follow_distance = 1200.0
		ai.engage_range = 10000.0
		ship.add_child(ai)
		
		# 添加交互控制器和模块管理器
		if not ship.get_node_or_null("InteractionController"):
			var ic = Node.new()
			ic.name = "InteractionController"
			ic.set_script(preload("res://scripts/ui/InteractionController.gd"))
			ship.add_child(ic)
		if not ship.get_node_or_null("ModuleManager"):
			var mm = Node.new()
			mm.name = "ModuleManager"
			mm.set_script(preload("res://scripts/modules/ModuleManager.gd"))
			ship.add_child(mm)
		
		# 生成在玩家附近
		var offset = Vector3(randf_range(-600.0, 600.0), 0, randf_range(-600.0, 600.0))
		ship.name = "AllyShip_Summoned"
		main.add_child(ship)
		ship.global_position = leader.global_position + offset
		
		# 注册到舰队管理器
		fm.register_player_ship(ship)
		
		# 如果有选中的舰队，自动加入
		if _selected_fleet_id >= 0:
			fm.add_ship_to_fleet(ship, _selected_fleet_id)
		
		# 显示消息
		var hud = get_node_or_null("/root/SpaceWar/HUD")
		if hud and hud.has_method("add_message"):
			hud.add_message("召唤友军: %s" % ship.ship_data.ship_name, Color(0.3, 0.8, 1))
		
		_refresh()

## 直接生成友军飞船（备用方案）
func _spawn_ally_ship_direct(ship_class: ShipData.ShipClass, leader: Ship) -> void:
	var scene = Global.get_player_ship_scene(ship_class)
	var ship = scene.instantiate()
	
	ship.ship_data = ShipData.get_preset(ship_class)
	ship.ship_data.ship_name = Ship.generate_random_name(ship_class)
	ship.faction = Ship.Faction.PLAYER
	ship.faction_name = FleetManager.PLAYER_FACTION_NAME
	
	var ai = AllyAI.new()
	ship.add_child(ai)
	
	var main = get_node_or_null("/root/SpaceWar")
	if not main:
		return
	
	var offset = Vector3(randf_range(-600.0, 600.0), 0, randf_range(-600.0, 600.0))
	ship.name = "AllyShip_Direct"
	main.add_child(ship)
	ship.global_position = leader.global_position + offset
	
	var fm = get_node_or_null("/root/FleetManager")
	if fm:
		fm.register_player_ship(ship)
		if _selected_fleet_id >= 0:
			fm.add_ship_to_fleet(ship, _selected_fleet_id)
