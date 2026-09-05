# world_object_base.gd —— 通用物体基础调度实体 (所有树木、农作物、建筑、道具的基类，对标 creature_base.gd)
class_name WorldObjectBase
extends Node2D

# === 基础空间属性 (所有物体核心状态) ===
@export_group("网格定位与占地尺寸")
## 物体占地尺寸 (1, 1)=小麦, (2, 2)=灌木, (4, 4)=大树
@export var grid_size: Vector2i = Vector2i(4, 4)
## 在大网格内部的具体子格坐标 (0~3, 0~3)
@export var sub_cell: Vector2i = Vector2i(0, 0)
## 物体脚底基准世界坐标 (放置时自动计算)
@export var base_position: Vector2 = Vector2.ZERO
## 物体所在楼层高度 (0=地面, 1=一层台上...)
@export var floor_level: int = 0

# === 物理立面遮挡高度 ===
@export_group("物理立面高度 (Obstacle Height)")
## 物体自身的立体遮挡高度 (像素)。用于 2.5D 视线阴影投射计算。
## 秋季大树约为 48px~60px；单层砖石方块约为 16px；低矮农作物/小麦约为 8px。
@export var obstacle_height: float = 48.0

# === 破坏与掉落属性 ===
@export_group("破坏与掉落配置")
## 是否随地砖被挖而连带瓦解（小麦/花草 = true，大树/巨石 = false）
@export var break_with_tile: bool = true
## 自身被破坏时掉落的物品 ID（如 "wheat", "wood"）
@export var drop_item_id: String = ""
## 掉落数量
@export var drop_count: int = 1

# === 2.5D 深度排序核心变量 (供 sort_world.gd 排序使用) ===
var sort_key: float = 0.0
var layer_no: int = 999
var foot_y: float = 0.0

# 模块化功能组件引用 (支持即时懒查找，即使在 _ready 之前访问也不会为 null)
var placement_comp: ObjectPlacementComponent:
	get:
		if _placement_comp == null:
			_placement_comp = _find_placement_comp()
		return _placement_comp
	set(v):
		_placement_comp = v

var xray_comp: ObjectXRayComponent:
	get:
		if _xray_comp == null:
			_xray_comp = _find_xray_comp()
		return _xray_comp
	set(v):
		_xray_comp = v

var destructible_comp: ObjectDestructibleComponent:
	get:
		if _destructible_comp == null:
			_destructible_comp = _find_destructible_comp()
		return _destructible_comp
	set(v):
		_destructible_comp = v

var _placement_comp: ObjectPlacementComponent = null
var _xray_comp: ObjectXRayComponent = null
var _destructible_comp: ObjectDestructibleComponent = null

func _ready() -> void:
	# 确保组件已被检索
	if placement_comp == null:
		_placement_comp = _find_placement_comp()
	if xray_comp == null:
		_xray_comp = _find_xray_comp()
	if destructible_comp == null:
		_destructible_comp = _find_destructible_comp()

	# 同步可破坏属性组件
	if destructible_comp:
		if drop_item_id == "" and destructible_comp.drop_item_id != "":
			drop_item_id = destructible_comp.drop_item_id
		elif drop_item_id != "":
			destructible_comp.drop_item_id = drop_item_id

		if drop_count == 1 and destructible_comp.drop_count != 1:
			drop_count = destructible_comp.drop_count
		elif drop_count != 1:
			destructible_comp.drop_count = drop_count

		break_with_tile = destructible_comp.break_with_tile

	# 1. 计算物体空间位置与排序键
	if placement_comp:
		var result := placement_comp.calculate_placement()
		global_position = result["position"]
		sort_key = result["sort_key"]
		foot_y = result["foot_y"]
	else:
		# 无定位组件时的兜底计算
		if base_position == Vector2.ZERO and position != Vector2.ZERO:
			base_position = position
		if floor_level == 0 and not GridData.layers.is_empty():
			var c := GridData.world_to_cell(base_position)
			var hf := GridData.get_highest_floor(c)
			if hf > 0:
				floor_level = hf
		var base_key := GridData.cell_to_sort_key(GridData.world_to_cell(base_position))
		var center_u := float(sub_cell.x) + float(grid_size.x) * 0.5
		var center_v := float(sub_cell.y) + float(grid_size.y) * 0.5
		var sub_depth := ((center_u + center_v) / 8.0) * 15.0
		global_position = base_position + Vector2(0.0, GridData.get_floor_pixel_offset(floor_level))
		foot_y = global_position.y
		sort_key = base_key + sub_depth

	# 2. 注册进场景深度排序
	var parent_sort := get_parent()
	if parent_sort and parent_sort.has_method("insert_sort"):
		parent_sort.call("insert_sort", self)

func _find_placement_comp() -> ObjectPlacementComponent:
	return find_child("ObjectPlacementComponent", true, false) as ObjectPlacementComponent

func _find_xray_comp() -> ObjectXRayComponent:
	return find_child("ObjectXRayComponent", true, false) as ObjectXRayComponent

func _find_destructible_comp() -> ObjectDestructibleComponent:
	return find_child("ObjectDestructibleComponent", true, false) as ObjectDestructibleComponent
