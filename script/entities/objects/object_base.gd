# object_base.gd —— 可排序物体基类(树/石头/掉落物等)
extends Node2D

# 物体脚底的平面位置(格子中心的世界坐标,不含楼层偏移)
@export var base_position: Vector2 = Vector2.ZERO

# 物体所在楼层
@export var floor_level: int = 0

# 排序次键:物体永远后画(盖住自己站的地形)
var layer_no: int = 999

# 排序主键:所在格基底屏幕 y
var sort_key: float = 0.0

# 精确脚底屏幕 y(同格实体间比较用;支持格内任意位置)
var foot_y: float = 0.0

func _ready() -> void:
	# 自动给树冠挂透视 shader（只给 Canopy 挂，树干保持实心）
	var canopy := get_node_or_null("Canopy") as Sprite2D
	if canopy == null:
		canopy = get_node_or_null("Sprite2D") as Sprite2D # 兼容旧物体
	if canopy and canopy.material == null:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://script/shaders/xray.gdshader")
		canopy.material = mat

	# 如果存在碰撞体,把它抵消到格平面(树视觉在顶面,碰撞停在格平面)
	var collision_node := get_node_or_null("StaticBody2D")
	if collision_node:
		collision_node.position.y = float(floor_level + 1) * GridData.FLOOR_HEIGHT

	global_position = base_position + Vector2(0.0, GridData.get_floor_pixel_offset(floor_level))
	foot_y = global_position.y
	sort_key = GridData.cell_to_sort_key(GridData.world_to_cell(base_position))
	# 自动加入排序
	var parent_sort := get_parent()
	if parent_sort and parent_sort.has_method("insert_sort"):
		parent_sort.insert_sort(self)
		
	add_to_group("xray_objects")
	
	# 注册到该格的占用表
	GridData.register_object(GridData.world_to_cell(base_position), self)