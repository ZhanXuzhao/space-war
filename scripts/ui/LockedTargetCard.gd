extends Panel
class_name LockedTargetCard

## 锁定目标卡片 - 显示锁定目标的图标、名称、护盾/装甲/结构/电容

signal card_clicked(target: Ship)

var bound_target: Ship = null

## 船型图标映射
const SHIP_ICONS := {
	ShipData.ShipClass.FRIGATE: preload("res://images/icon_frigate.png"),
	ShipData.ShipClass.CRUISER: preload("res://images/icon_cruiser.png"),
	ShipData.ShipClass.BATTLESHIP: preload("res://images/icon_battleship.png"),
}

@onready var icon_rect: TextureRect = $VBox/IconRect
@onready var name_label: Label = $VBox/NameLabel
@onready var shield_bar: ProgressBar = $VBox/ShieldBar
@onready var armor_bar: ProgressBar = $VBox/ArmorBar
@onready var hull_bar: ProgressBar = $VBox/HullBar
@onready var capacitor_bar: ProgressBar = $VBox/CapacitorBar

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	# 如果 setup 在 _ready 之前已被调用，刷新显示
	if bound_target:
		update_bars(bound_target)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if bound_target and is_instance_valid(bound_target):
			card_clicked.emit(bound_target)

## 使用目标数据初始化卡片
func setup(target: Ship) -> void:
	bound_target = target
	
	if icon_rect:
		icon_rect.modulate = Color.WHITE
		var cls = target.ship_data.ship_class if target.ship_data else ShipData.ShipClass.FRIGATE
		var icon = SHIP_ICONS.get(cls)
		icon_rect.texture = icon
	
	if name_label:
		name_label.text = target.ship_data.ship_name if target.ship_data else "未知"
	
	update_bars(target)

## 更新四条状态条
func update_bars(target: Ship) -> void:
	if not target:
		return
	if shield_bar:
		shield_bar.value = (target.current_shield / target.max_shield) * 100.0 if target.max_shield > 0 else 0.0
	if armor_bar:
		armor_bar.value = (target.current_armor / target.max_armor) * 100.0 if target.max_armor > 0 else 0.0
	if hull_bar:
		hull_bar.value = (target.current_hull / target.max_hull) * 100.0 if target.max_hull > 0 else 0.0
	if capacitor_bar:
		capacitor_bar.value = (target.current_capacitor / target.max_capacitor) * 100.0 if target.max_capacitor > 0 else 0.0

## 设置选中高亮样式
func set_selected(selected: bool) -> void:
	add_theme_stylebox_override("panel", _make_card_bg_style(selected))

## 创建卡片背景样式
func _make_card_bg_style(selected: bool = false) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.2, 0.85)
	style.border_color = _get_ship_color(bound_target) if bound_target else Color(0.7, 0.7, 0.7)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	if selected:
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.bg_color = Color(0.2, 0.2, 0.3, 0.9)
		style.shadow_color = style.border_color
		style.shadow_size = 6
		style.shadow_offset = Vector2(0, 0)
	return style

## 根据飞船阵营返回颜色
func _get_ship_color(target: Ship) -> Color:
	match target.faction:
		Ship.Faction.NPC_HOSTILE:
			return Color(1, 0.3, 0.3)
		Ship.Faction.NPC_FRIENDLY:
			return Color(0.3, 1, 0.3)
		Ship.Faction.PLAYER:
			return Color(0.3, 0.8, 1)
		_:
			return Color(0.7, 0.7, 0.7)
