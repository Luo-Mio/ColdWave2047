# height_step_limit_component.gd —— 生物楼层高低差跨越限制与悬崖阻挡组件
class_name HeightStepLimitComponent
extends Node

@export_group("楼层高低差跨越限制 (Height Step Limit)")
## 是否启用高度差限制
@export var is_enabled: bool = true
## 最大允许上下跨越楼层数 (上下落差超过该层数的格子将视为不可跨越的高墙或悬崖，默认 4 层)
@export var max_step_height: int = 4
## 是否同时阻挡未铺设任何地砖的虚空深渊 (默认 true)
@export var block_void: bool = true
## 是否允许沿无法进入的高墙/悬崖边缘平滑滑动 (默认 true)
@export var enable_sliding: bool = true
## 身体足底防穿模安全边距 (像素，默认 4.0px)
@export var margin_pixels: float = 4.0

var entity: CharacterBody2D = null
var _last_physics_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	# 向上查找所属生物实体
	var curr := get_parent()
	while curr:
		if curr is CharacterBody2D:
			entity = curr as CharacterBody2D
			break
		curr = curr.get_parent()
	if entity:
		_last_physics_pos = entity.global_position

func _physics_process(_delta: float) -> void:
	if not is_enabled or entity == null:
		return
	# 兜底守护：如果父实体未通过 MoverComponent 移动，此处确保物理边界不被非法穿透
	enforce_boundary(entity, _last_physics_pos)
	_last_physics_pos = entity.global_position

# 获取 GridData 引用 (兼容主场景运行与独立单元测试环境)
func _get_grid() -> Node:
	var tree := get_tree()
	if tree and tree.root and tree.root.has_node("GridData"):
		return tree.root.get_node("GridData")
	return null

# 检验目标格子是否允许从 from_floor 楼层合法通行
func is_cell_passable(target_cell: Vector2i, from_floor: int) -> bool:
	var gd = _get_grid()
	if gd == null:
		return true

	if block_void and gd.has_method("has_any_tile"):
		if not gd.call("has_any_tile", target_cell):
			return false

	var target_floor: int = 0
	if gd.has_method("get_highest_floor"):
		target_floor = gd.call("get_highest_floor", target_cell)

	return absi(target_floor - from_floor) <= max_step_height

# 物理移动前的速度预处理：检测前方目标落点，若撞向不可进入的格子，则消除法向速度并投影至等距切向平滑滑动
func constrain_velocity(current_pos: Vector2, velocity: Vector2, delta: float) -> Vector2:
	if not is_enabled or velocity == Vector2.ZERO:
		return velocity

	var gd = _get_grid()
	if gd == null or not gd.has_method("world_to_cell") or not gd.has_method("get_highest_floor"):
		return velocity

	var curr_cell: Vector2i = gd.call("world_to_cell", current_pos)
	var curr_floor: int = gd.call("get_highest_floor", curr_cell)

	var motion := velocity * delta
	var target_pos := current_pos + motion
	var probe_pos := target_pos + velocity.normalized() * margin_pixels
	var probe_cell: Vector2i = gd.call("world_to_cell", probe_pos)

	# 若探测点在同一格子内，完全合法
	if probe_cell == curr_cell:
		return velocity

	# 若探测点所在格子不可通行（上下落差超过 max_step_height，或为虚空）
	if not is_cell_passable(probe_cell, curr_floor):
		# 计算该边界的外法线（由 2:1 等距几何推导：normal = (dx * 0.5, dy * 2.0).normalized()）
		var center_probe: Vector2 = gd.call("cell_to_world", probe_cell)
		var center_curr: Vector2 = gd.call("cell_to_world", curr_cell)
		var cell_delta := center_probe - center_curr
		if cell_delta == Vector2.ZERO:
			return Vector2.ZERO
		var normal := Vector2(cell_delta.x * 0.5, cell_delta.y * 2.0).normalized()
		var dot_n := velocity.dot(normal)

		if enable_sliding and dot_n > 0.0:
			# 消除撞墙法向分量，投影到等距边缘切线
			var slide_vel := velocity - normal * dot_n
			# 二次校验：确保沿切线滑动时不会撞向另一个障碍角
			var probe2 := current_pos + slide_vel * delta + slide_vel.normalized() * margin_pixels
			var cell2: Vector2i = gd.call("world_to_cell", probe2)
			if cell2 != curr_cell and not is_cell_passable(cell2, curr_floor):
				return Vector2.ZERO
			return slide_vel
		else:
			return Vector2.ZERO

	return velocity

# 物理移动后的二次兜底保险：使用二分法快速定位合法边界，杜绝任何外力击退或高速穿模
func enforce_boundary(body: CharacterBody2D, prev_pos: Vector2) -> void:
	if not is_enabled or body == null:
		return

	var gd = _get_grid()
	if gd == null or not gd.has_method("world_to_cell") or not gd.has_method("get_highest_floor"):
		return

	var curr_pos := body.global_position
	var curr_cell: Vector2i = gd.call("world_to_cell", curr_pos)
	var prev_cell: Vector2i = gd.call("world_to_cell", prev_pos)

	# 依然在原格子里，安全
	if curr_cell == prev_cell:
		return

	var prev_floor: int = gd.call("get_highest_floor", prev_cell)
	if not is_cell_passable(curr_cell, prev_floor):
		# 发生了非法穿墙/跌落，二分法寻找边界接触点并弹回合法区域内
		var low := prev_pos
		var high := curr_pos
		for i in range(6):
			var mid := (low + high) * 0.5
			var mid_cell: Vector2i = gd.call("world_to_cell", mid)
			if is_cell_passable(mid_cell, prev_floor):
				low = mid
			else:
				high = mid
		body.global_position = low
		body.velocity = Vector2.ZERO
