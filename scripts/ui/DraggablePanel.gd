extends Panel
class_name DraggablePanel

## 可拖拽移动、边缘拉伸缩放的容器面板
## 按照约定自动寻找子节点：
##   - HeaderBg (Panel)     → 标题栏，拖拽移动手柄
##   - HandleLeft (Control)  → 左边拉伸手柄
##   - HandleRight (Control) → 右边拉伸手柄
##   - HandleTop (Control)   → 上边拉伸手柄
##   - HandleBottom (Control)→ 下边拉伸手柄

signal layout_changed()

## 最小尺寸限制
@export var min_width: float = 100.0
@export var min_height: float = 80.0

var _header: Control = null
var _handles: Dictionary = {}  # "left"/"right"/"top"/"bottom" → Control

var _is_dragging: bool = false
var _is_resizing: bool = false

var _drag_start_mouse: Vector2
var _drag_start_offset: Vector2  # panel (offset_left, offset_top)

var _resize_start_x: float
var _resize_start_y: float
var _resize_start_left: float
var _resize_start_right: float
var _resize_start_top: float
var _resize_start_bottom: float


func _ready() -> void:
	# 按约定查找标题栏 → 拖拽手柄
	_header = _find_child_control("HeaderBg")
	if _header:
		_header.mouse_filter = Control.MOUSE_FILTER_STOP
		_header.gui_input.connect(_on_header_input)
	
	# 按约定查找四边拉伸手柄
	for edge in ["left", "right", "top", "bottom"]:
		var handle_name = "Handle" + edge.capitalize()
		var h = _find_child_control(handle_name)
		if h:
			_handles[edge] = h
			h.gui_input.connect(_on_handle_input.bind(edge))


## 查找直接子节点中的 Control（仅限直接子节点）
func _find_child_control(name: String) -> Control:
	for child in get_children():
		if child is Control and child.name == name:
			return child
	return null


## ====== 拖拽移动 ======

func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_is_dragging = true
			_drag_start_mouse = get_viewport().get_mouse_position()
			_drag_start_offset = Vector2(offset_left, offset_top)
		else:
			_is_dragging = false
			layout_changed.emit()
	
	if event is InputEventMouseMotion and _is_dragging:
		var mouse_pos = get_viewport().get_mouse_position()
		var delta = mouse_pos - _drag_start_mouse
		var w = offset_right - offset_left
		var h = offset_bottom - offset_top
		offset_left = _drag_start_offset.x + delta.x
		offset_right = offset_left + w
		offset_top = _drag_start_offset.y + delta.y
		offset_bottom = offset_top + h


## ====== 边缘拉伸缩放 ======

## 获取面板当前绝对坐标（相对视口左上角）
func _get_abs_rect() -> Rect2:
	var vp = get_viewport().get_visible_rect().size
	var l = offset_left if anchor_left <= 0.5 else vp.x + offset_left
	var r = offset_right if anchor_right <= 0.5 else vp.x + offset_right
	var t = offset_top if anchor_top <= 0.5 else vp.y + offset_top
	var b = offset_bottom if anchor_bottom <= 0.5 else vp.y + offset_bottom
	return Rect2(l, t, r - l, b - t)

func _on_handle_input(event: InputEvent, edge: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_is_resizing = true
			var mpos = get_viewport().get_mouse_position()
			_resize_start_x = mpos.x
			_resize_start_y = mpos.y
			# 统一转换为绝对坐标后再计算（兼容任意锚点设置）
			var abs_rect = _get_abs_rect()
			_resize_start_left = abs_rect.position.x
			_resize_start_right = abs_rect.position.x + abs_rect.size.x
			_resize_start_top = abs_rect.position.y
			_resize_start_bottom = abs_rect.position.y + abs_rect.size.y
		else:
			_is_resizing = false
			layout_changed.emit()
	
	if event is InputEventMouseMotion and _is_resizing:
		var mpos = get_viewport().get_mouse_position()
		var dx = mpos.x - _resize_start_x
		var dy = mpos.y - _resize_start_y
		var vp = get_viewport().get_visible_rect().size
		
		# 在绝对坐标中计算新位置
		var abs_l = _resize_start_left
		var abs_r = _resize_start_right
		var abs_t = _resize_start_top
		var abs_b = _resize_start_bottom
		
		match edge:
			"left":
				abs_l = _resize_start_left + dx
				abs_l = clampf(abs_l, -vp.x * 0.5, _resize_start_right - min_width)
			"right":
				abs_r = _resize_start_right + dx
				abs_r = clampf(abs_r, _resize_start_left + min_width, vp.x - 10.0)
			"top":
				abs_t = _resize_start_top + dy
				abs_t = clampf(abs_t, 30.0, _resize_start_bottom - min_height)
			"bottom":
				abs_b = _resize_start_bottom + dy
				abs_b = clampf(abs_b, _resize_start_top + min_height, vp.y - 10.0)
		
		# 将绝对坐标转换回 offset（根据锚点类型）
		offset_left = abs_l if anchor_left <= 0.5 else abs_l - vp.x
		offset_right = abs_r if anchor_right <= 0.5 else abs_r - vp.x
		offset_top = abs_t if anchor_top <= 0.5 else abs_t - vp.y
		offset_bottom = abs_b if anchor_bottom <= 0.5 else abs_b - vp.y
