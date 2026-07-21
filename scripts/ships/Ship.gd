extends CharacterBody3D
class_name Ship

## 飞船基类 - 包含所有飞船共有的属性和行为

signal shield_changed(current: float, max_value: float)
signal armor_changed(current: float, max_value: float)
signal hull_changed(current: float, max_value: float)
signal capacitor_changed(current: float, max_value: float)
signal ship_destroyed()
signal target_locked(target: Ship)
signal target_lost(target: Ship)

## 飞船基础属性
@export var ship_data: ShipData
@export var max_shield: float = 800.0
@export var max_armor: float = 600.0
@export var max_hull: float = 800.0
@export var max_capacitor: float = 400.0
@export var capacitor_recharge: float = 20.0  # 每秒恢复量
@export var max_speed: float = 1000.0
@export var acceleration: float = 100.0
@export var deceleration: float = 50.0
@export var rotation_speed: float = 2.0
@export var cargo_capacity: float = 500.0
@export var signature_radius: float = 40.0
@export var max_locked_targets: int = 8

## 当前状态
var current_shield: float
var current_armor: float
var current_hull: float
var current_capacitor: float
var current_speed: float = 0.0
var is_alive: bool = true

## 移动控制（由 PlayerController 或 AIController 驱动）
var has_move_order: bool = false
var move_target: Vector3 = Vector3.ZERO

## 持续靠近目标（非空时每帧更新 move_target，实现追踪移动目标）
var approach_target: Node3D = null
## 靠近停止距离（进入此范围后停止推进，避免贴脸抖动）
@export var approach_range: float = 500.0

## 速度指令模式（用于环绕时径向/切向速度分配）
var has_velocity_order: bool = false
var velocity_setpoint: Vector3 = Vector3.ZERO

## 目标与战斗
var locked_targets: Array[Ship] = []
var active_target: Ship = null
var target_lock_progress: float = 0.0  # 0.0 ~ 1.0
var is_target_locking: bool = false
var current_targeting_range: float = 20000.0  # 锁定距离

## 模块与武器
var high_slot_modules: Array[Node] = []
var mid_slot_modules: Array[Node] = []
var low_slot_modules: Array[Node] = []
var weapon_nodes: Array[Node] = []

## 飞船模型尺寸常量（与场景中碰撞箱尺寸一致）
## 注意：飞船根节点已通过 _apply_model_scale() 设置了 scale = model_scale
## 炮台作为子节点，局部坐标使用碰撞箱原始尺寸即可，父节点缩放会自动作用于子节点
const SHIP_LENGTH: float = 300.0
const SHIP_HALF_WIDTH: float = 75.0

## LOD（Level of Detail）- 远距离使用图标代替3D模型
## 当距离 > 飞船尺寸 × lod_distance_multiplier 时切换为图标
## 值从 game_config.cfg [lod] distance_multiplier 加载
var lod_distance_multiplier: float = 50.0

## 图标纹理路径（按船型）
const ICON_PATH_FRIGATE: String = "res://images/icon_tiny_frigate.svg"
const ICON_PATH_CRUISER: String = "res://images/icon_tiny_cruiser.svg"
const ICON_PATH_BATTLESHIP: String = "res://images/icon_tiny_battleship.svg"

## 3D模型节点引用（GLB实例）
var _model_node: Node3D = null
## LOD图标
var _lod_icon: Sprite3D = null
## 图标纹理缓存
var _icon_frigate: Texture2D = null
var _icon_cruiser: Texture2D = null
var _icon_battleship: Texture2D = null

## 防重复初始化标记（脚本热替换时使用）
var _initialized: bool = false

## 速度箭头
var _velocity_arrow: MeshInstance3D

## 船头标记圆球（在场景中定义，代码仅控制阵营颜色）
var _nose_sphere: MeshInstance3D

## 战术网格图（XZ平面同心圆 + 十字线）
var _tactical_grid: MeshInstance3D
## 敌方飞船到战术网格面的垂线
var _drop_lines: MeshInstance3D
## 战术网格半径列表（单位：米）
const TACTICAL_GRID_RADII: Array[float] = [5000.0, 10000.0, 20000.0, 30000.0, 40000.0, 50000.0, 75000.0, 100000.0, 150000.0, 200000.0]
## 半径数字标签列表（用于每帧更新固定屏幕大小）
var _range_labels: Array[Label3D] = []
## 半径数字的反缩放系数（用于 _process 中计算标签缩放）
## 战术网格标签字体大小（从 game_config.cfg 加载）
var _tactical_grid_label_font_size: float = 300000.0
var _range_label_scale_inv: float = 1.0

## 移动预览 - 目标位置小圆环（Q+鼠标时显示）
var _move_preview_circle: MeshInstance3D
## 移动预览 - 飞船到目标的连线（Q+鼠标时显示）
var _move_preview_line: MeshInstance3D
## 是否正在显示移动目标的持久预览（点击后到抵达前持续显示）
var _show_move_target_preview: bool = false

## 接近目标连线
var _approach_line: MeshInstance3D

## 阵营
enum Faction { PLAYER, NPC_FRIENDLY, NPC_HOSTILE, NEUTRAL }
@export var faction: Faction = Faction.NEUTRAL

func _ready() -> void:
	if _initialized:
		return
	_initialized = true
	_init_stats()
	_create_default_equipment()
	_setup_velocity_arrow()
	_setup_nose_color()
	if faction == Faction.PLAYER:
		_setup_tactical_grid()
		_setup_move_preview()
	_setup_lod()

## LOD 初始化：查找3D模型节点，创建图标精灵
func _setup_lod() -> void:
	# 查找GLB模型实例节点（第一个 scene_file_path 非空的子节点）
	for child in get_children():
		if child is Node3D and not child.scene_file_path.is_empty():
			_model_node = child
			break
	
	# 加载图标纹理
	if ResourceLoader.exists(ICON_PATH_FRIGATE):
		_icon_frigate = load(ICON_PATH_FRIGATE)
	if ResourceLoader.exists(ICON_PATH_CRUISER):
		_icon_cruiser = load(ICON_PATH_CRUISER)
	if ResourceLoader.exists(ICON_PATH_BATTLESHIP):
		_icon_battleship = load(ICON_PATH_BATTLESHIP)
	
	# 创建 Sprite3D 图标（初始隐藏）
	_lod_icon = Sprite3D.new()
	_lod_icon.name = "LodIcon"
	_lod_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED  # 始终面向摄像机
	_lod_icon.no_depth_test = true  # 不被其他物体遮挡
	_lod_icon.visible = false
	add_child(_lod_icon)
	
	# 根据船型设置对应图标纹理
	var tex: Texture2D = null
	if ship_data:
		match ship_data.ship_class:
			ShipData.ShipClass.FRIGATE:
				tex = _icon_frigate
			ShipData.ShipClass.CRUISER:
				tex = _icon_cruiser
			ShipData.ShipClass.BATTLESHIP:
				tex = _icon_battleship
	_lod_icon.texture = tex
	
	# 从 game_config.cfg 加载LOD参数
	var cfg = ConfigFile.new()
	if cfg.load("res://resources/game_config.cfg") == OK:
		var val = cfg.get_value("lod", "distance_multiplier", 50.0)
		lod_distance_multiplier = float(val)
	
	# 根据阵营设置图标颜色
	_update_lod_icon_tint()

## 根据阵营设置图标颜色
func _update_lod_icon_tint() -> void:
	if not _lod_icon:
		return
	match faction:
		Faction.PLAYER:
			_lod_icon.modulate = Color(0.2, 0.6, 1.0)  # 蓝色
		Faction.NPC_HOSTILE:
			_lod_icon.modulate = Color(1.0, 0.2, 0.1)  # 红色
		Faction.NPC_FRIENDLY:
			_lod_icon.modulate = Color(0.2, 1.0, 0.3)  # 绿色
		Faction.NEUTRAL:
			_lod_icon.modulate = Color(1.0, 1.0, 1.0)  # 白色

## 随机飞船名字池（按船型，由 ShipData.SHIP_CLASS_NAMES_POOL 管理）
## 公开接口：根据船型获取随机名字（供 EnemySpawner 等外部调用）
static func generate_random_name(ship_class: ShipData.ShipClass) -> String:
	return _get_random_name(ship_class)

func _init_stats() -> void:
	# 如果没有 ship_data，根据阵营自动生成一个合适船型的默认数据
	if not ship_data:
		ship_data = _create_default_ship_data()
	
	# 从 ship_data 应用属性到飞船
	_apply_ship_data()
	
	# 初始化当前值
	current_shield = max_shield
	current_armor = max_armor
	current_hull = max_hull
	current_capacitor = max_capacitor

## 根据阵营和船型生成默认 ShipData
func _create_default_ship_data() -> ShipData:
	var default_class: ShipData.ShipClass
	
	# NPC 敌对飞船随机分配船型（护卫舰/巡洋舰各半）
	if faction == Faction.NPC_HOSTILE:
		var roll = randf()
		if roll < 0.5:        # 50% 护卫舰
			default_class = ShipData.ShipClass.FRIGATE
		else:                  # 50% 巡洋舰
			default_class = ShipData.ShipClass.CRUISER
	else:
		default_class = ShipData.ShipClass.FRIGATE
	
	var data = ShipData.get_preset(default_class)
	data.ship_name = _get_random_name(data.ship_class)
	return data

## 将 ShipData 的属性应用到飞船的导出变量上
func _apply_ship_data() -> void:
	if not ship_data:
		return
	
	max_shield = ship_data.shield_hp
	max_armor = ship_data.armor_hp
	max_hull = ship_data.hull_hp
	max_capacitor = ship_data.capacitor_max
	capacitor_recharge = ship_data.capacitor_recharge_rate
	max_speed = ship_data.max_speed
	cargo_capacity = ship_data.cargo_capacity
	signature_radius = ship_data.signature_radius
	max_locked_targets = ship_data.max_locked_targets
	
	# 根据船型调整机动性
	match ship_data.ship_class:
		ShipData.ShipClass.FRIGATE:
			acceleration = 200.0
			deceleration = 100.0
			rotation_speed = 3.0
			approach_range = 300.0
		ShipData.ShipClass.CRUISER:
			acceleration = 80.0
			deceleration = 40.0
			rotation_speed = 1.5
			approach_range = 600.0
		ShipData.ShipClass.BATTLESHIP:
			acceleration = 30.0
			deceleration = 15.0
			rotation_speed = 0.6
			approach_range = 1000.0
	
	# 应用模型缩放
	_apply_model_scale()

## 根据 ship_data.model_scale 缩放飞船模型
## 直接缩放根节点，碰撞体和视觉子节点自动跟随
func _apply_model_scale() -> void:
	if not ship_data:
		return
	scale = Vector3.ONE * ship_data.model_scale

## 根据船型和阵营创建默认装备（武器 + 维修模块）
## 敌我双方共用，创建逻辑由 ship_data 和 faction 决定
func _create_default_equipment() -> void:
	if not ship_data:
		return
	
	var hardpoints = ship_data.turret_hardpoints
	if hardpoints <= 0:
		return
	
	# 玩家阵营：激光 + 导弹混装 + 维修模块
	if faction == Faction.PLAYER:
		var laser_count = int(hardpoints / 2.0)
		var missile_count = int(hardpoints / 2.0)
		# 传递全局起始索引和总硬点数，确保所有炮台在 Z 轴上等距分布
		_create_laser_weapons(laser_count, 0, hardpoints)
		_create_missile_weapons(missile_count, laser_count, hardpoints)
		_create_repair_modules()
	# NPC：激光 + 导弹各一半
	else:
		var laser_count = int(hardpoints / 2.0)
		var missile_count = hardpoints - laser_count
		_create_npc_weapons(laser_count, 0, hardpoints)
		_create_npc_missile_weapons(missile_count, laser_count, hardpoints)

## 根据船型获取激光武器参数
func _get_laser_stats() -> Dictionary:
	var cls = ship_data.ship_class if ship_data else ShipData.ShipClass.FRIGATE
	match cls:
		ShipData.ShipClass.FRIGATE:
			return { "name": "小型激光炮", "damage": 25.0, "rof": 3.0, "optimal": 5000.0, "falloff": 10000.0, "tracking": 1.0, "cap": 5.0 }
		ShipData.ShipClass.CRUISER:
			return { "name": "中型激光炮", "damage": 55.0, "rof": 4.0, "optimal": 10000.0, "falloff": 15000.0, "tracking": 0.8, "cap": 12.0 }
		ShipData.ShipClass.BATTLESHIP:
			return { "name": "大型激光炮", "damage": 120.0, "rof": 5.0, "optimal": 20000.0, "falloff": 25000.0, "tracking": 0.5, "cap": 25.0 }
	return {}

## 根据船型获取导弹武器参数
func _get_missile_stats() -> Dictionary:
	var cls = ship_data.ship_class if ship_data else ShipData.ShipClass.FRIGATE
	match cls:
		ShipData.ShipClass.FRIGATE:
			return { "name": "轻型导弹发射器", "damage": 60.0, "rof": 6.0, "optimal": 5000.0, "falloff": 8000.0, "tracking": 0.5, "sig": 40.0, "cap": 15.0, "proj_scale": 0.6, "speed": 2000.0 }
		ShipData.ShipClass.CRUISER:
			return { "name": "中型导弹发射器", "damage": 140.0, "rof": 8.0, "optimal": 10000.0, "falloff": 15000.0, "tracking": 0.4, "sig": 80.0, "cap": 30.0, "proj_scale": 1.0, "speed": 2000.0 }
		ShipData.ShipClass.BATTLESHIP:
			return { "name": "重型导弹发射器", "damage": 300.0, "rof": 10.0, "optimal": 20000.0, "falloff": 30000.0, "tracking": 0.3, "sig": 150.0, "cap": 50.0, "proj_scale": 1.8, "speed": 2000.0 }
	return {}

## 根据船型获取NPC武器参数
func _get_npc_weapon_stats() -> Dictionary:
	var cls = ship_data.ship_class if ship_data else ShipData.ShipClass.FRIGATE
	match cls:
		ShipData.ShipClass.FRIGATE:
			return { "name": "小型NPC激光炮", "damage": 15.0, "rof": 3.0, "optimal": 5000.0, "falloff": 10000.0, "tracking": 1.0, "cap": 2.0 }
		ShipData.ShipClass.CRUISER:
			return { "name": "中型NPC激光炮", "damage": 40.0, "rof": 4.0, "optimal": 10000.0, "falloff": 15000.0, "tracking": 0.8, "cap": 6.0 }
		ShipData.ShipClass.BATTLESHIP:
			return { "name": "大型NPC激光炮", "damage": 80.0, "rof": 5.0, "optimal": 20000.0, "falloff": 25000.0, "tracking": 0.5, "cap": 12.0 }
	return {}

## 创建NPC激光武器
func _create_npc_weapons(count: int, start_index: int, total_hardpoints: int) -> void:
	var stats = _get_npc_weapon_stats()
	for i in range(count):
		var weapon = Weapon.new()
		var wdata = WeaponData.new()
		wdata.weapon_name = stats["name"]
		wdata.damage = stats["damage"]
		wdata.damage_type = "热能"
		wdata.rate_of_fire = 1.0 / stats["rof"]
		wdata.optimal_range = stats["optimal"]
		wdata.falloff_range = stats["falloff"]
		wdata.tracking_speed = stats["tracking"]
		wdata.capacitor_usage = stats["cap"]
		wdata.projectile_scene = null
		weapon.weapon_data = wdata
		_install_turret_weapon(weapon, start_index + i, total_hardpoints, "NPCLaser")

## 根据船型获取NPC导弹武器参数
func _get_npc_missile_stats() -> Dictionary:
	var cls = ship_data.ship_class if ship_data else ShipData.ShipClass.FRIGATE
	match cls:
		ShipData.ShipClass.FRIGATE:
			return { "name": "轻型NPC导弹", "damage": 40.0, "rof": 6.0, "optimal": 5000.0, "falloff": 8000.0, "tracking": 0.5, "sig": 40.0, "cap": 8.0, "proj_scale": 0.6, "speed": 2000.0 }
		ShipData.ShipClass.CRUISER:
			return { "name": "中型NPC导弹", "damage": 100.0, "rof": 8.0, "optimal": 10000.0, "falloff": 15000.0, "tracking": 0.4, "sig": 80.0, "cap": 15.0, "proj_scale": 1.0, "speed": 2000.0 }
		ShipData.ShipClass.BATTLESHIP:
			return { "name": "重型NPC导弹", "damage": 200.0, "rof": 10.0, "optimal": 20000.0, "falloff": 30000.0, "tracking": 0.3, "sig": 150.0, "cap": 25.0, "proj_scale": 1.8, "speed": 2000.0 }
	return {}

## 创建NPC导弹武器
func _create_npc_missile_weapons(count: int, start_index: int, total_hardpoints: int) -> void:
	var stats = _get_npc_missile_stats()
	var projectile_scene = preload("res://scenes/weapons/Missile.tscn")
	for i in range(count):
		var weapon = Weapon.new()
		var wdata = WeaponData.new()
		wdata.weapon_name = stats["name"]
		wdata.weapon_type = WeaponData.WeaponType.MISSILE
		wdata.damage = stats["damage"]
		wdata.damage_type = "爆炸"
		wdata.rate_of_fire = 1.0 / stats["rof"]
		wdata.optimal_range = stats["optimal"]
		wdata.falloff_range = stats["falloff"]
		wdata.tracking_speed = stats["tracking"]
		wdata.signature_resolution = stats["sig"]
		wdata.capacitor_usage = stats["cap"]
		wdata.projectile_scene = projectile_scene
		wdata.projectile_scale = stats["proj_scale"]
		wdata.projectile_speed = stats["speed"]
		weapon.weapon_data = wdata
		_install_turret_weapon(weapon, start_index + i, total_hardpoints, "NPCMissile")

## 创建激光武器，沿飞船左右对称分布
func _create_laser_weapons(count: int, start_index: int, total_hardpoints: int) -> void:
	var stats = _get_laser_stats()
	for i in range(count):
		var weapon = Weapon.new()
		var wdata = WeaponData.new()
		wdata.weapon_name = stats["name"]
		wdata.damage = stats["damage"]
		wdata.damage_type = "热能"
		wdata.rate_of_fire = 1.0 / stats["rof"]
		wdata.optimal_range = stats["optimal"]
		wdata.falloff_range = stats["falloff"]
		wdata.tracking_speed = stats["tracking"]
		wdata.capacitor_usage = stats["cap"]
		wdata.projectile_scene = null
		weapon.weapon_data = wdata
		_install_turret_weapon(weapon, start_index + i, total_hardpoints, "LaserWeapon")

## 创建导弹武器，沿飞船左右对称分布
func _create_missile_weapons(count: int, start_index: int, total_hardpoints: int) -> void:
	var stats = _get_missile_stats()
	var projectile_scene = preload("res://scenes/weapons/Missile.tscn")
	for i in range(count):
		var weapon = Weapon.new()
		var wdata = WeaponData.new()
		wdata.weapon_name = stats["name"]
		wdata.description = stats["name"] + "，自动追踪导弹"
		wdata.weapon_type = WeaponData.WeaponType.MISSILE
		wdata.damage = stats["damage"]
		wdata.damage_type = "爆炸"
		wdata.rate_of_fire = 1.0 / stats["rof"]
		wdata.optimal_range = stats["optimal"]
		wdata.falloff_range = stats["falloff"]
		wdata.tracking_speed = stats["tracking"]
		wdata.signature_resolution = stats["sig"]
		wdata.capacitor_usage = stats["cap"]
		wdata.projectile_scene = projectile_scene
		wdata.projectile_scale = stats["proj_scale"]
		wdata.projectile_speed = stats["speed"]
		weapon.weapon_data = wdata
		# 导弹和激光使用相同的 Z 范围，确保所有炮台等距分布
		_install_turret_weapon(weapon, start_index + i, total_hardpoints, "MissileLauncher")

## 根据船型获取维修装备参数
func _get_repair_module_stats() -> Dictionary:
	var cls = ship_data.ship_class if ship_data else ShipData.ShipClass.FRIGATE
	match cls:
		ShipData.ShipClass.FRIGATE:
			return {
				"prefix": "轻型",
				"shield": { "amount": 120.0, "cap": 30.0, "time": 3.0 },
				"armor":  { "amount": 80.0,  "cap": 35.0, "time": 3.0 },
				"structure": { "amount": 60.0, "cap": 40.0, "time": 3.0 },
			}
		ShipData.ShipClass.CRUISER:
			return {
				"prefix": "中型",
				"shield": { "amount": 300.0, "cap": 60.0, "time": 3.0 },
				"armor":  { "amount": 200.0, "cap": 70.0, "time": 3.0 },
				"structure": { "amount": 150.0, "cap": 80.0, "time": 3.0 },
			}
		ShipData.ShipClass.BATTLESHIP:
			return {
				"prefix": "重型",
				"shield": { "amount": 6000.0, "cap": 120.0, "time": 3.0 },  # 护盾维修量x10
				"armor":  { "amount": 4000.0, "cap": 140.0, "time": 3.0 },
				"structure": { "amount": 3000.0, "cap": 160.0, "time": 3.0 },
			}
	return {}

## 创建3个维修装备：护盾维修、装甲维修、结构维修（按船型分大中小）
func _create_repair_modules() -> void:
	var stats = _get_repair_module_stats()
	var prefix = stats.get("prefix", "轻型")
	var modules_info = [
		{ "cls": ShieldBooster,    "key": "shield",    "name": prefix + "护盾维修器" },
		{ "cls": ArmorRepairer,    "key": "armor",     "name": prefix + "装甲维修器" },
		{ "cls": StructureRepairer, "key": "structure", "name": prefix + "结构维修器" },
	]
	for info in modules_info:
		var s = stats[info["key"]]
		var mod: ShipModule = info["cls"].new()
		var mdata = ModuleData.new()
		mdata.module_name = info["name"]
		mdata.effect_amount = s["amount"]
		mdata.capacitor_usage = s["cap"]
		mdata.activation_time = s["time"]
		mdata.slot_type = ModuleData.ModuleSlot.LOW
		mod.module_data = mdata
		mod.name = info["name"]
		add_child(mod)
		low_slot_modules.append(mod)

## 射击所有武器
func fire_weapons(target: Ship, delta: float) -> void:
	for weapon in weapon_nodes:
		if weapon is Weapon:
			weapon.try_fire(target, delta)

## 在指定炮台硬点位置安装武器（敌我共用）
## 自动计算左右交替位置，沿船身前后分布
## @param weapon:        要安装的 Weapon 节点
## @param index:         硬点序号（0 开始）
## @param total:         硬点总数
## @param name_prefix:   武器名前缀
## @param z_start:       船头方向 Z 偏移比例（负值=前方），默认 -0.4
## @param z_end:         船尾方向 Z 偏移比例（正值=后方），默认 0.6
func _install_turret_weapon(weapon: Weapon, index: int, total: int,
		name_prefix: String, z_start: float = -0.4, z_end: float = 0.6) -> void:
	var side = 1 if index % 2 == 0 else -1
	var pair_idx = index / 2
	var pairs = total / 2
	
	var z_offset = SHIP_LENGTH * z_start
	if pairs > 1:
		z_offset += (float(pair_idx) / (pairs - 1)) * SHIP_LENGTH * (z_end - z_start)
	
	weapon.position = Vector3(SHIP_HALF_WIDTH * side, 0, z_offset)
	weapon.name = "%s_%s_%d" % [name_prefix, "Left" if side > 0 else "Right", pair_idx]
	weapon.mount_local_normal = Vector3(side, 0, 0)
	add_child(weapon)
	weapon_nodes.append(weapon)
	weapon.activate()

static var _frigate_index: int = 0
static var _cruiser_index: int = 0
static var _battleship_index: int = 0

static func _get_random_name(ship_class: ShipData.ShipClass) -> String:
	var pool = ShipData.SHIP_CLASS_NAMES_POOL.get(ship_class, ShipData.SHIP_CLASS_NAMES_POOL[ShipData.ShipClass.FRIGATE])
	var idx: int
	match ship_class:
		ShipData.ShipClass.FRIGATE:
			idx = _frigate_index % pool.size()
			_frigate_index += 1
		ShipData.ShipClass.CRUISER:
			idx = _cruiser_index % pool.size()
			_cruiser_index += 1
		ShipData.ShipClass.BATTLESHIP:
			idx = _battleship_index % pool.size()
			_battleship_index += 1
		_:
			idx = _frigate_index % pool.size()
			_frigate_index += 1
	return pool[idx] + "级"

## 创建速度箭头（绿色锥体，方向朝前，长度随速度变化）
func _setup_velocity_arrow() -> void:
	var cone = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 5.0
	cone.height = 25.0
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 1.0, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(0.0, 1.0, 0.2)
	mat.emission_energy_multiplier = 0.5
	cone.material = mat
	
	_velocity_arrow = MeshInstance3D.new()
	_velocity_arrow.mesh = cone
	# ConeMesh 默认朝 +Y，旋转使其朝 -Z（飞船前进方向）
	_velocity_arrow.rotate_x(deg_to_rad(90.0))
	# 放在飞船前方（飞船长300m，前端在z=-150）
	_velocity_arrow.position.z = -180.0
	add_child(_velocity_arrow)

func _process(delta: float) -> void:
	if not is_alive:
		return
	_recharge_capacitor(delta)
	_update_lod()
	_update_velocity_arrow()
	_update_approach(delta)
	_update_approach_line()
	_update_range_labels()
	# 更新环绕轨迹圆环的反旋转（敌方飞船也会旋转，需保持 XZ 水平）
	_update_orbit_trajectory_world_aligned()
	if faction == Faction.PLAYER:
		_update_drop_lines()
		_update_tactical_grid_world_aligned()
	# 移动目标持久预览：飞船移动时持续更新连线，抵达后自动隐藏
	if _show_move_target_preview:
		if has_move_order and is_alive:
			# 如果没按住 Q，由飞船自己更新预览；按住 Q 时由 InteractionController 控制
			if not Input.is_key_pressed(KEY_Q):
				show_move_preview(move_target)
		else:
			# 移动完成或取消，清除持久预览
			_show_move_target_preview = false
			hide_move_preview()

## LOD 更新：根据摄像机距离切换3D模型/2D图标
## 图标在屏幕上保持固定大小（约16像素），并随阵营着色
func _update_lod() -> void:
	if not _model_node or not _lod_icon:
		return
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return
	
	var cam_distance = global_position.distance_to(camera.global_position)
	
	# 飞船实际尺寸 = 基础长度 × 缩放系数
	var ship_real_length = SHIP_LENGTH * maxf(scale.x, 0.01)
	var lod_threshold = ship_real_length * lod_distance_multiplier
	
	var use_icon = cam_distance > lod_threshold
	
	if _model_node.visible == use_icon:
		# 需要切换状态
		_model_node.visible = not use_icon
		_lod_icon.visible = use_icon
	
	# 图标固定屏幕大小：根据距离动态调整 pixel_size
	# 公式：pixel_size = desired_pixels * 2 * dist * tan(FOV/2) / (tex_width * viewport_height)
	# 目标屏幕像素设为 16，图标纹理 32x32，所以 desired_pixels / tex_width = 0.5
	# 注意：Sprite3D 是飞船子节点，会继承父节点 scale，需要除以 scale 抵消
	var viewport = get_viewport()
	var viewport_height = viewport.get_visible_rect().size.y
	if viewport_height > 0:
		var fov_half = deg_to_rad(camera.fov) * 0.5
		var parent_scale = maxf(scale.x, 0.01)
		_lod_icon.pixel_size = cam_distance * tan(fov_half) / viewport_height / parent_scale

## 更新速度箭头：速度越快箭头越长
func _update_velocity_arrow() -> void:
	if not _velocity_arrow:
		return
	var speed_ratio = clampf(current_speed / max_speed, 0.0, 1.0)
	# 最小为 0.1（静止时可见小点），最大为 1.0（全速）
	var scale_len = 0.1 + speed_ratio * 0.9
	_velocity_arrow.scale.z = scale_len
	_velocity_arrow.scale.x = 0.3 + speed_ratio * 0.7
	_velocity_arrow.scale.y = 0.3 + speed_ratio * 0.7
	_velocity_arrow.visible = speed_ratio > 0.01

## 设置船头圆球颜色（按阵营，圆球本身在场景中定义）
func _setup_nose_color() -> void:
	_nose_sphere = get_node_or_null("NoseSphere") as MeshInstance3D
	if not _nose_sphere:
		return
	
	var mat = _nose_sphere.get_surface_override_material(0)
	if not mat:
		mat = StandardMaterial3D.new()
		_nose_sphere.set_surface_override_material(0, mat)
	
	mat.emission_enabled = true
	mat.emission_energy_multiplier = 1.5
	match faction:
		Faction.PLAYER:
			mat.albedo_color = Color(0.2, 0.6, 1.0)
			mat.emission = Color(0.2, 0.6, 1.0)
		Faction.NPC_HOSTILE:
			mat.albedo_color = Color(1.0, 0.2, 0.1)
			mat.emission = Color(1.0, 0.2, 0.1)
		Faction.NPC_FRIENDLY:
			mat.albedo_color = Color(0.2, 1.0, 0.3)
			mat.emission = Color(0.2, 1.0, 0.3)
		_:  # NEUTRAL
			mat.albedo_color = Color(0.8, 0.8, 0.8)
			mat.emission = Color(0.8, 0.8, 0.8)

## 创建战术网格图（XZ平面同心圆 + 十字线，始终跟随飞船）
func _setup_tactical_grid() -> void:
	# 飞船根节点有 model_scale 缩放，子节点坐标会被放大
	# 此处用反缩放系数抵消，确保网格距离为真实世界距离
	var scale_inv = 1.0 / maxf(scale.x, 0.01)
	_range_label_scale_inv = scale_inv
	
	_tactical_grid = MeshInstance3D.new()
	_tactical_grid.name = "TacticalGrid"
	add_child(_tactical_grid)
	
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	
	var grid_color = Color(1.0, 1.0, 1.0, 0.25)
	var segments = 64
	
	# 绘制同心圆（XZ平面）
	for radius in TACTICAL_GRID_RADII:
		var r = radius * scale_inv
		for i in range(segments):
			var t1 = (2.0 * PI * i) / segments
			var t2 = (2.0 * PI * (i + 1)) / segments
			var p1 = Vector3(cos(t1) * r, 0.0, sin(t1) * r)
			var p2 = Vector3(cos(t2) * r, 0.0, sin(t2) * r)
			st.add_vertex(p1)
			st.add_vertex(p2)
	
	# 绘制X轴直线（左右方向）
	var max_radius = TACTICAL_GRID_RADII[TACTICAL_GRID_RADII.size() - 1] * scale_inv
	var line_segments = 128
	for i in range(line_segments):
		var t = lerpf(-max_radius, max_radius, float(i) / line_segments)
		var t_next = lerpf(-max_radius, max_radius, float(i + 1) / line_segments)
		st.add_vertex(Vector3(t, 0.0, 0.0))
		st.add_vertex(Vector3(t_next, 0.0, 0.0))
	
	# 绘制Z轴直线（前后方向）
	for i in range(line_segments):
		var t = lerpf(-max_radius, max_radius, float(i) / line_segments)
		var t_next = lerpf(-max_radius, max_radius, float(i + 1) / line_segments)
		st.add_vertex(Vector3(0.0, 0.0, t))
		st.add_vertex(Vector3(0.0, 0.0, t_next))
	
	var mesh = st.commit()
	
	# 半透明白色材质
	var mat = StandardMaterial3D.new()
	mat.albedo_color = grid_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.surface_set_material(0, mat)
	
	_tactical_grid.mesh = mesh
	
	# 在每道圆形内侧添加距离数字标签
	var label_color = Color(1.0, 1.0, 1.0, 0.9)
	# 从 game_config.cfg 加载战术网格标签字体大小
	var cfg = ConfigFile.new()
	if cfg.load("res://resources/game_config.cfg") == OK:
		var val = cfg.get_value("tactical_grid", "label_font_size", 300000)
		_tactical_grid_label_font_size = float(val)
	for radius in TACTICAL_GRID_RADII:
		var km = int(radius / 1000.0)
		var sys_font = SystemFont.new()
		sys_font.font_names = ["Arial", "Segoe UI", "Microsoft YaHei"]
		sys_font.font_weight = 700
		var font = FontVariation.new()
		font.base_font = sys_font
		var r = radius * scale_inv
		var y = 15.0 * scale_inv
		var dirs = [
			Vector3( r, y, 0.0),  # X+
			Vector3(-r, y, 0.0),  # X-
			Vector3(0.0, y,  r),  # Z+
			Vector3(0.0, y, -r),  # Z-
		]
		for pos in dirs:
			var label = Label3D.new()
			label.name = "RangeLabel_%d_%d_%d" % [km, int(pos.x), int(pos.z)]
			label.text = "%dkm" % km
			label.font = font
			label.font_size = _tactical_grid_label_font_size
			label.outline_size = 8
			label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
			label.modulate = label_color
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			label.position = pos
			label.scale = Vector3.ONE * scale_inv
			add_child(label)
			# 记录标签的原始局部偏移，用于每帧反旋转保持世界对齐
			label.set_meta("world_offset", pos)
			_range_labels.append(label)
	
	# 创建敌方飞船到网格面的垂线网格实例
	_drop_lines = MeshInstance3D.new()
	_drop_lines.name = "DropLines"
	add_child(_drop_lines)
	# 半透明白色材质（稍细更亮，以便与十字线区分）
	var drop_mat = StandardMaterial3D.new()
	drop_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.4)
	drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_drop_lines.material_override = drop_mat

## 每帧反旋转战术网格，使其永远水平于世界坐标系（Y轴垂直、XZ线平行世界）
func _update_tactical_grid_world_aligned() -> void:
	if not _tactical_grid or not _tactical_grid.visible:
		return
	# 提取飞船旋转的逆，仅抵消旋转，保留位置和缩放继承
	var inv_rot = Basis(global_basis.get_rotation_quaternion().inverse())
	_tactical_grid.transform.basis = inv_rot
	_drop_lines.transform.basis = inv_rot
	for label in _range_labels:
		if not label.has_meta("world_offset"):
			continue
		var orig_offset: Vector3 = label.get_meta("world_offset")
		label.position = inv_rot * orig_offset

## 更新敌方飞船到战术网格面（XZ平面）的弧线
## 以我方为圆心、敌我距离为半径，在敌我所在的垂直平面内画弧，从敌方位置落到 XZ 网格面
func _update_drop_lines() -> void:
	if not _drop_lines or not is_inside_tree():
		return
	if not _tactical_grid or not _tactical_grid.visible:
		_drop_lines.visible = false
		return
	_drop_lines.visible = true
	
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	
	var root = get_tree().current_scene
	if not root:
		return
	
	_append_drop_lines_recursive(root, st)
	
	var mesh = st.commit()
	_drop_lines.mesh = mesh

## 递归扫描场景树，为所有敌方飞船添加圆弧
func _append_drop_lines_recursive(node: Node, st: SurfaceTool) -> void:
	for child in node.get_children():
		if child is Ship and child != self and child.faction == Ship.Faction.NPC_HOSTILE and child.is_alive:
			_draw_drop_arc(st, child)
		# 递归继续搜索子节点
		_append_drop_lines_recursive(child, st)

## 为单艘敌船绘制圆弧
## 圆心 = 玩家原点，半径 = 敌我距离，
## 平面 = 敌我所在的垂直平面，从敌船位置落到 XZ 网格面（y=0）
func _draw_drop_arc(st: SurfaceTool, enemy: Ship) -> void:
	# 使用世界空间相对坐标而非 to_local()，避免玩家飞船旋转导致弧线错位
	var local_pos = enemy.global_position - global_position
	var r = local_pos.length()
	if r < 1.0:
		return
	
	# 水平方向单位向量（从玩家指向敌船在地面的投影点）
	var h_dir = Vector3(local_pos.x, 0.0, local_pos.z)
	var h_dist = h_dir.length()
	if h_dist < 0.001:
		# 敌船几乎在正上方/正下方 → 水平方向任意取一个
		h_dir = Vector3.FORWARD
		h_dist = 0.0
	else:
		h_dir = h_dir / h_dist
	
	# 敌船与水平面的夹角（仰角）
	var theta = atan2(local_pos.y, h_dist)  # 范围 (-PI/2, PI/2)
	
	# 从 theta 到 0 的圆弧段数
	var segments = 24
	var step = theta / segments
	
	for i in range(segments):
		var a1 = theta - step * i
		var a2 = theta - step * (i + 1)
		
		# 圆弧上的点 = 水平分量 + 垂直分量
		var p1 = r * cos(a1) * h_dir + Vector3(0.0, r * sin(a1), 0.0)
		var p2 = r * cos(a2) * h_dir + Vector3(0.0, r * sin(a2), 0.0)
		
		st.add_vertex(p1)
		st.add_vertex(p2)
	
	# 在弧线末端（XZ 网格面）画一个小圆圈
	var center = r * h_dir
	var circle_radius = 50  # 不超过 150 单位
	var circle_segments = 16
	for i in range(circle_segments):
		var a1 = (2.0 * PI * i) / circle_segments
		var a2 = (2.0 * PI * (i + 1)) / circle_segments
		var c1 = center + Vector3(cos(a1) * circle_radius, 0.0, sin(a1) * circle_radius)
		var c2 = center + Vector3(cos(a2) * circle_radius, 0.0, sin(a2) * circle_radius)
		st.add_vertex(c1)
		st.add_vertex(c2)

## 每帧更新半径标签缩放，使其屏幕大小不随镜头距离变化
func _update_range_labels() -> void:
	if _range_labels.is_empty():
		return
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return
	var cam_dist = global_position.distance_to(camera.global_position)
	# 以 80000 为参考距离，标签在此距离时 scale = scale_inv（即世界 scale = 1）
	var ref_dist = 80000.0
	var dist_ratio = cam_dist / ref_dist
	for label in _range_labels:
		label.scale = Vector3.ONE * _range_label_scale_inv * dist_ratio

## 基础移动逻辑（所有飞船共用）
## 由 PlayerController._physics_process / AIController._physics_process 调用
## 控制器通过 order_move_to/order_set_velocity 间接控制
func _handle_movement(delta: float) -> void:
	if has_velocity_order:
		# 速度指令模式：面向速度方向并加速到目标速度
		var target_speed = velocity_setpoint.length()
		if target_speed > 0.01:
			var target_dir = velocity_setpoint / target_speed
			var target_basis = Basis.looking_at(target_dir, Vector3.UP).orthonormalized()
			global_basis = global_basis.orthonormalized().slerp(target_basis, rotation_speed * delta)
			current_speed = move_toward(current_speed, target_speed, acceleration * delta)
		else:
			current_speed = move_toward(current_speed, 0.0, deceleration * delta)
		velocity = -global_basis.z * current_speed
	elif has_move_order:
		var direction = move_target - global_position
		var distance = direction.length()
		
		# 保护：目标方向为零向量时跳过旋转
		if distance < 0.001:
			current_speed = move_toward(current_speed, 0.0, deceleration * delta)
			velocity = -global_basis.z * current_speed
			move_and_slide()
			return
		direction = direction / distance
		
		# 飞船朝向目标方向旋转（平滑旋转）
		var target_basis = Basis.looking_at(direction, Vector3.UP).orthonormalized()
		global_basis = global_basis.orthonormalized().slerp(target_basis, rotation_speed * delta)
		
		# 接近目标时减速
		var speed_factor = 1.0
		if distance < 200.0:
			speed_factor = distance / 200.0
		# 持续靠近模式下不自动停止
		if distance < 50.0 and not approach_target:
			has_move_order = false
		
		# 防超出：如果这一帧会飞过目标，直接归位
		var move_this_frame = current_speed * delta
		if move_this_frame > distance and distance > 0.01:
			global_position = move_target
			current_speed = 0.0
			velocity = Vector3.ZERO
			has_move_order = false
		else:
			current_speed = move_toward(current_speed, max_speed * speed_factor, acceleration * delta)
			velocity = -global_basis.z * current_speed
	else:
		# 减速
		current_speed = move_toward(current_speed, 0.0, deceleration * delta)
		velocity = -global_basis.z * current_speed
	
	move_and_slide()

func _recharge_capacitor(delta: float) -> void:
	if current_capacitor < max_capacitor:
		current_capacitor = minf(max_capacitor, current_capacitor + capacitor_recharge * delta)
		capacitor_changed.emit(current_capacitor, max_capacitor)

## 受到伤害
func take_damage(damage: float, _damage_type: String, _attacker: Node) -> void:
	if not is_alive:
		return
	
	var remaining = damage
	
	# 护盾吸收
	if current_shield > 0:
		var shield_damage = minf(current_shield, remaining)
		current_shield -= shield_damage
		remaining -= shield_damage
		shield_changed.emit(current_shield, max_shield)
	
	# 装甲吸收
	if remaining > 0 and current_armor > 0:
		var armor_damage = minf(current_armor, remaining)
		current_armor -= armor_damage
		remaining -= armor_damage
		armor_changed.emit(current_armor, max_armor)
	
	# 结构伤害
	if remaining > 0:
		current_hull -= remaining
		hull_changed.emit(current_hull, max_hull)
		if current_hull <= 0:
			_destroy()

func _destroy() -> void:
	is_alive = false
	ship_destroyed.emit()
	# 爆炸效果
	_spawn_explosion()
	queue_free()

func _spawn_explosion() -> void:
	## 创建爆炸特效
	## 根据船型和阵营自动选择大小和颜色
	# 检查全局设置：是否显示爆炸特效
	var g = get_node_or_null("/root/Global")
	if g and not g.explosion_visible:
		return
	var explosion_scene = preload("res://scenes/effects/Explosion.tscn")
	if not explosion_scene:
		return
	
	var explosion = explosion_scene.instantiate() as Explosion
	get_tree().root.add_child(explosion)
	explosion.global_position = global_position
	
	# 根据船型设置爆炸大小
	if ship_data:
		match ship_data.ship_class:
			ShipData.ShipClass.FRIGATE:
				explosion.size = Explosion.ExplosionSize.MEDIUM
			ShipData.ShipClass.CRUISER:
				explosion.size = Explosion.ExplosionSize.LARGE
			ShipData.ShipClass.BATTLESHIP:
				explosion.size = Explosion.ExplosionSize.HUGE
			_:
				explosion.size = Explosion.ExplosionSize.MEDIUM
	
	# 根据阵营设置爆炸颜色
	match faction:
		Faction.PLAYER:
			explosion.faction_color = Color(0.2, 0.6, 1.0)     # 蓝白
		Faction.NPC_HOSTILE:
			explosion.faction_color = Color(1.0, 0.4, 0.05)    # 橙红
		Faction.NPC_FRIENDLY:
			explosion.faction_color = Color(0.3, 1.0, 0.3)     # 绿
		_:
			explosion.faction_color = Color(1.0, 0.6, 0.1)     # 默认橙黄

## 锁定目标
func lock_target(target: Ship) -> bool:
	if not target.is_alive:
		return false
	# 清理已失效的锁定目标引用
	_cleanup_locked_targets()
	if locked_targets.size() >= max_locked_targets:
		return false
	if target in locked_targets:
		return true
	
	var distance = global_position.distance_to(target.global_position)
	if distance > current_targeting_range:
		return false
	
	locked_targets.append(target)
	target_locked.emit(target)
	return true

func unlock_target(target: Ship) -> void:
	locked_targets.erase(target)
	if active_target == target:
		active_target = null
	target_lost.emit(target)

## 清理已失效的锁定目标（被摧毁/freed 的引用）
func _cleanup_locked_targets() -> void:
	locked_targets = locked_targets.filter(func(t): return is_instance_valid(t) and t.is_alive)

func set_active_target(target: Ship) -> void:
	if target in locked_targets:
		active_target = target

## 持续靠近目标（每帧更新 move_target = target.global_position，实现追击）
func order_approach(target: Node3D) -> void:
	if not target or not is_instance_valid(target):
		return
	approach_target = target
	move_target = target.global_position
	has_move_order = true
	has_velocity_order = false

## 取消持续靠近
func cancel_approach() -> void:
	approach_target = null

## 每帧更新靠近目标位置（进入 approach_range 后停止推进，避免贴脸抖动）
func _update_approach(_delta: float) -> void:
	if not approach_target or not is_instance_valid(approach_target):
		approach_target = null
		return
	var dist = global_position.distance_to(approach_target.global_position)
	if dist < approach_range:
		# 计算刹车距离：v² / (2 * deceleration)，防止高速时太早取消导致冲出太远
		var stopping_dist = (current_speed * current_speed) / (2.0 * maxf(deceleration, 1.0))
		if dist < stopping_dist:
			# 已进入刹车区 → 取消靠近，减速滑停
			approach_target = null
			has_move_order = false
			return
		# 距离足够宽裕，继续靠近
	move_target = approach_target.global_position

## 移动到目标位置（由 PlayerController/AIController 调用）
func order_move_to(position: Vector3) -> void:
	approach_target = null
	move_target = position
	has_move_order = true
	has_velocity_order = false
	# 启用移动目标持久预览（抵达后自动消失）
	_show_move_target_preview = true
	show_move_preview(position)

## 速度指令模式：直接指定目标速度向量（用于环绕径向/切向分配）
func order_set_velocity(target_velocity: Vector3) -> void:
	has_velocity_order = true
	has_move_order = false
	velocity_setpoint = target_velocity

## 使用电容
func use_capacitor(amount: float) -> bool:
	if current_capacitor >= amount:
		current_capacitor -= amount
		capacitor_changed.emit(current_capacitor, max_capacitor)
		return true
	return false

## 获取信息
func get_hull_percent() -> float:
	return current_hull / max_hull * 100.0

func get_armor_percent() -> float:
	return current_armor / max_armor * 100.0

func get_shield_percent() -> float:
	return current_shield / max_shield * 100.0

func get_capacitor_percent() -> float:
	return current_capacitor / max_capacitor * 100.0

# ---------------------------------------------------------------------------
# 环绕轨迹可视化
# ---------------------------------------------------------------------------
var _trajectory_instance: MeshInstance3D = null

## 显示环绕轨迹圆环（围绕目标，水平面上的圆形）
func show_orbit_trajectory(radius: float = 1200.0, color: Color = Color(0.3, 0.8, 1.0)) -> void:
	if not _trajectory_instance:
		_trajectory_instance = MeshInstance3D.new()
		_trajectory_instance.name = "OrbitTrajectory"
		add_child(_trajectory_instance)

	# 用 SurfaceTool 构建线条网格（水平圆形）
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)

	var segments = 64
	for i in range(segments):
		var t1 = (2.0 * PI * i) / segments
		var t2 = (2.0 * PI * (i + 1)) / segments

		var p1 = Vector3(cos(t1) * radius, 0.0, sin(t1) * radius)
		var p2 = Vector3(cos(t2) * radius, 0.0, sin(t2) * radius)

		st.add_vertex(p1)
		st.add_vertex(p2)

	var mesh = st.commit()

	# 发光半透明材质
	var mat = ORMMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.5)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.2
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.surface_set_material(0, mat)

	_trajectory_instance.mesh = mesh
	# 抵消飞船旋转，使圆环始终保持在水平 XZ 平面
	_trajectory_instance.transform.basis = Basis(global_basis.get_rotation_quaternion().inverse())
	_trajectory_instance.visible = true

## 每帧反旋转环绕轨迹圆环，使其始终保持在水平 XZ 平面
func _update_orbit_trajectory_world_aligned() -> void:
	if not _trajectory_instance or not _trajectory_instance.visible:
		return
	var inv_rot = Basis(global_basis.get_rotation_quaternion().inverse())
	_trajectory_instance.transform.basis = inv_rot

## 隐藏环绕轨迹
func hide_orbit_trajectory() -> void:
	if _trajectory_instance:
		_trajectory_instance.visible = false

## 切换环绕轨迹显示
func toggle_orbit_trajectory(visible: bool, radius: float = 1200.0) -> void:
	if visible:
		show_orbit_trajectory(radius)
	else:
		hide_orbit_trajectory()

# ---------------------------------------------------------------------------
# Q+鼠标 移动预览（小圆 + 连线）
# ---------------------------------------------------------------------------

## 初始化移动预览视觉元素
func _setup_move_preview() -> void:
	_move_preview_circle = MeshInstance3D.new()
	_move_preview_circle.name = "MovePreviewCircle"
	add_child(_move_preview_circle)
	_move_preview_circle.visible = false

	_move_preview_line = MeshInstance3D.new()
	_move_preview_line.name = "MovePreviewLine"
	add_child(_move_preview_line)
	_move_preview_line.visible = false

	# 接近目标连线
	_approach_line = MeshInstance3D.new()
	_approach_line.name = "ApproachLine"
	add_child(_approach_line)
	_approach_line.visible = false

## 显示移动预览（在目标世界位置画小圆 + 从飞船到目标的连线）
func show_move_preview(world_target: Vector3) -> void:
	if not _move_preview_circle or not _move_preview_line:
		return
	if not _tactical_grid or not _tactical_grid.visible:
		hide_move_preview()
		return

	var local_target = to_local(world_target)
	var preview_color = Color(0.3, 1.0, 0.5, 0.9)  # 亮绿色半透明
	var circle_radius = 100.0
	var segments = 32

	# --- 更新目标小圆环 ---
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	for i in range(segments):
		var a1 = (2.0 * PI * i) / segments
		var a2 = (2.0 * PI * (i + 1)) / segments
		var p1 = Vector3(cos(a1) * circle_radius, 0.0, sin(a1) * circle_radius)
		var p2 = Vector3(cos(a2) * circle_radius, 0.0, sin(a2) * circle_radius)
		st.add_vertex(p1 + local_target)
		st.add_vertex(p2 + local_target)
	var mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = preview_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.surface_set_material(0, mat)
	_move_preview_circle.mesh = mesh
	_move_preview_circle.visible = true

	# --- 更新飞船到目标的连线 ---
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	st.add_vertex(Vector3.ZERO)  # 飞船原点（局部坐标）
	st.add_vertex(local_target)
	mesh = st.commit()
	mat = StandardMaterial3D.new()
	mat.albedo_color = preview_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.surface_set_material(0, mat)
	_move_preview_line.mesh = mesh
	_move_preview_line.visible = true

## 隐藏移动预览
func hide_move_preview() -> void:
	if _show_move_target_preview:
		return  # 有持久预览时跳过隐藏，由抵达逻辑自动清除
	if _move_preview_circle:
		_move_preview_circle.visible = false
	if _move_preview_line:
		_move_preview_line.visible = false

# ---------------------------------------------------------------------------
# 接近目标连线
# ---------------------------------------------------------------------------

## 每帧更新接近目标连线
func _update_approach_line() -> void:
	if approach_target and is_instance_valid(approach_target):
		if not _approach_line.visible:
			_approach_line.visible = true
		_draw_approach_line()
	else:
		if _approach_line and _approach_line.visible:
			_approach_line.visible = false

## 绘制接近连线（从飞船到目标）
func _draw_approach_line() -> void:
	if not approach_target or not is_instance_valid(approach_target):
		_approach_line.visible = false
		return
	
	var local_target = to_local(approach_target.global_position)
	var color = Color(0.3, 1.0, 0.5, 0.8)  # 亮绿色半透明
	
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	st.add_vertex(Vector3.ZERO)  # 飞船原点
	st.add_vertex(local_target)
	var mesh = st.commit()
	
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.5
	mesh.surface_set_material(0, mat)
	
	_approach_line.mesh = mesh
