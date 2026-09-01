# object_base.gd —— 可排序物体基类(支持 4x4 子网格、树木、农作物等)
class_name WorldObject
extends Node2D

# 物体脚底的平面世界坐标
@export var base_position: Vector2 = Vector2.ZERO
# 物体所在楼层
@export var floor_level: int = 0

# 【核心占地尺寸】：(1, 1) = 占 1 个微格(如小麦)；(2, 2) = 占 4 个微格(如灌木)；(4, 4) = 占满整格(如大树)
@export_group("网格尺寸与子格")
@export var grid_size: Vector2i = Vector2i(4, 4)
@export var sub_cell: Vector2i = Vector2i(0, 0) # 在大格内的具体子格坐标 (0~3, 0~3)
# 随机抖动（花草/小麦建议开微小抖动，让麦田更自然）
@export_group("随机抖动偏移")
@export var enable_random_jitter: bool = false
@export var jitter_size: Vector2 = Vector2(2.0, 1.0) # 小麦建议 2x1，大树建议 6x3
@export_group("破坏与掉落属性")
@export var break_with_tile: bool = true  # 是否随地砖被挖而连带瓦解（小麦/花草 = true，大树/巨石 = false）
@export var drop_item_id: String = ""     # 自身被破坏时掉落的物品 ID（如 "wheat", "wood"）
@export var drop_count: int = 1           # 掉落数量

# 排序键
var layer_no: int = 999
var sort_key: float = 0.0
var foot_y: float = 0.0

func _ready() -> void:
	# 1. 严格锁定“整像素”随机微小偏移（仅作用于视觉显示，不破坏基准网格坐标）
	var jitter := Vector2.ZERO
	# 4x4 微格沿对角线的最大和为 4.0 + 4.0 = 8.0，精准映射为 0.0 ~ 15.0
	var base_key := GridData.cell_to_sort_key(GridData.world_to_cell(base_position))
	var center_u := float(sub_cell.x) + float(grid_size.x) * 0.5
	var center_v := float(sub_cell.y) + float(grid_size.y) * 0.5
	var sub_depth := ((center_u + center_v) / 8.0) * 15.0

	if enable_random_jitter:
		var rx := jitter_size.x * 0.5
		var ry := jitter_size.y * 0.5
		jitter = _get_random_diamond_offset(rx, ry)

	# 3. 碰撞体高度修正（如果有）
	var collision_node := get_node_or_null("StaticBody2D")
	if collision_node:
		collision_node.position.y = float(floor_level + 1) * GridData.FLOOR_HEIGHT

	# 4. 精确世界坐标与高精度微格排序键
	global_position = base_position + jitter + Vector2(0.0, GridData.get_floor_pixel_offset(floor_level))
	foot_y = global_position.y

	sort_key = base_key + sub_depth

	# 5. 加入排序
	var parent_sort := get_parent()
	if parent_sort and parent_sort.has_method("insert_sort"):
		parent_sort.call("insert_sort", self)
		
	add_to_group("xray_objects")

# 严格四舍五入到整像素的菱形随机偏移
func _get_random_diamond_offset(rx: float, ry: float) -> Vector2:
	while true:
		var pt := Vector2(randf_range(-rx, rx), randf_range(-ry, ry)).round()
		if rx > 0 and ry > 0:
			if (abs(pt.x) / rx) + (abs(pt.y) / ry) <= 1.0:
				return pt
		else:
			return Vector2.ZERO
	return Vector2.ZERO
