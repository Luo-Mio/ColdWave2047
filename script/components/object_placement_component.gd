# object_placement_component.gd —— 物体网格定位、微槽位与楼层高度计算组件
class_name ObjectPlacementComponent
extends Node

@export_group("网格定位与占地尺寸")
## 物体占地尺寸 (1, 1)=占1个微格(如小麦)；(2, 2)=占4个微格(如灌木)；(4, 4)=占满整格(如大树)
@export var grid_size: Vector2i = Vector2i(4, 4)
## 在 4x4 大网格内部的具体子格坐标 (0~3, 0~3)
@export var sub_cell: Vector2i = Vector2i(0, 0)
## 物体脚底基准世界坐标 (放置时自动计算)
@export var base_position: Vector2 = Vector2.ZERO
## 物体所在楼层高度 (0=地面, 1=一层台上...)
@export var floor_level: int = 0

@export_group("随机菱形抖动 (自然散落)")
## 是否开启随机整像素菱形微偏移 (花草/小麦等大片种植建议开启，使视觉更自然)
@export var enable_random_jitter: bool = false
## 随机抖动范围大小 (X: 水平像素, Y: 垂直像素，建议比例 2:1，如小麦 2x1，大树 16x12)
@export var jitter_size: Vector2 = Vector2(2.0, 1.0)

var parent_object: Node2D

func get_parent_object() -> Node2D:
	if parent_object == null:
		var curr := get_parent()
		while curr:
			if curr is Node2D:
				parent_object = curr as Node2D
				break
			curr = curr.get_parent()
	return parent_object

func _ready() -> void:
	get_parent_object()

# 计算物体的最终世界位置与排序信息
func calculate_placement() -> Dictionary:
	var obj := get_parent_object()

	# 1. 优先从父级实体同步/继承坐标与空间数据
	if obj:
		if "base_position" in obj and obj.base_position != Vector2.ZERO:
			base_position = obj.base_position
		elif base_position != Vector2.ZERO and "base_position" in obj:
			obj.base_position = base_position

		if "floor_level" in obj and obj.floor_level != 0:
			floor_level = obj.floor_level
		elif floor_level != 0 and "floor_level" in obj:
			obj.floor_level = floor_level

		if "grid_size" in obj:
			if grid_size != Vector2i(4, 4) and obj.grid_size == Vector2i(4, 4):
				obj.grid_size = grid_size
			else:
				grid_size = obj.grid_size

		if "sub_cell" in obj and obj.sub_cell != Vector2i.ZERO:
			sub_cell = obj.sub_cell
		elif sub_cell != Vector2i.ZERO and "sub_cell" in obj:
			obj.sub_cell = sub_cell

	# 2. 编辑器直接拖入场景时的防呆回退与楼层自动识别
	if base_position == Vector2.ZERO and obj and obj.position != Vector2.ZERO:
		base_position = obj.position
		if "base_position" in obj:
			obj.base_position = base_position

	if floor_level == 0 and not GridData.layers.is_empty():
		var c := GridData.world_to_cell(base_position)
		var hf := GridData.get_highest_floor(c)
		if hf > 0:
			floor_level = hf
			if obj and "floor_level" in obj:
				obj.floor_level = floor_level

	# 3. 随机整像素菱形微偏移 (自然散落)
	var jitter := Vector2.ZERO
	if enable_random_jitter:
		var rx := jitter_size.x * 0.5
		var ry := jitter_size.y * 0.5
		jitter = _get_random_diamond_offset(rx, ry)

	# 4. 4x4 微格沿对角线的最大和为 4.0 + 4.0 = 8.0，精准映射为 0.0 ~ 15.0 次级深度
	var base_key := GridData.cell_to_sort_key(GridData.world_to_cell(base_position))
	var center_u := float(sub_cell.x) + float(grid_size.x) * 0.5
	var center_v := float(sub_cell.y) + float(grid_size.y) * 0.5
	var sub_depth := ((center_u + center_v) / 8.0) * 15.0

	var final_pos := base_position + jitter + Vector2(0.0, GridData.get_floor_pixel_offset(floor_level))
	var sort_key: float = base_key + sub_depth
	var foot_y: float = final_pos.y

	return {
		"position": final_pos,
		"sort_key": sort_key,
		"foot_y": foot_y
	}

# 严格四舍五入到整像素的菱形随机偏移 (无浮点锯齿)
func _get_random_diamond_offset(rx: float, ry: float) -> Vector2:
	if rx <= 0.0 or ry <= 0.0:
		return Vector2.ZERO
	for attempt in 30:
		var pt := Vector2(randf_range(-rx, rx), randf_range(-ry, ry)).round()
		if (abs(pt.x) / rx) + (abs(pt.y) / ry) <= 1.0:
			return pt
	return Vector2.ZERO
