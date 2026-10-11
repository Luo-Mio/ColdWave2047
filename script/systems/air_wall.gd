# air_wall.gd —— 全自动地图边缘虚空空气墙生成器
class_name AirWallManager
extends Node2D

# 扫描 8 个相邻方向（上、下、左、右、4个斜角，严丝合缝无死角）
const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)
]

# 标准 64x32 菱形碰撞箱轮廓点
const DIAMOND_POINTS: PackedVector2Array = [
	Vector2(0, -16), Vector2(32, 0), Vector2(0, 16), Vector2(-32, 0)
]

func _ready() -> void:
	add_to_group("air_walls")

# 全自动重建边缘空气墙 (支持全楼层覆盖与多高度阶梯适配)
func rebuild_walls() -> void:
	# 1. 清理现有的碰撞体
	for child in get_children():
		child.queue_free()

	if GridData.grid.is_empty() and GridData.layers.is_empty():
		return

	# 2. 从所有图层收集包含瓷砖的 2D 大格子坐标（涵盖第 0 层至最高层所有陆地）
	var used_cells_set: Dictionary = {}
	for pos3: Vector3i in GridData.grid.keys():
		used_cells_set[Vector2i(pos3.x, pos3.y)] = true
	for layer in GridData.layers:
		for cell in layer.get_used_cells():
			used_cells_set[cell] = true

	if used_cells_set.is_empty():
		return

	# 3. 收集所有“紧邻有效陆地的空白虚空格”，并记录相邻陆地的最高楼层
	var void_cells: Dictionary = {}
	for cell in used_cells_set.keys():
		var cell_fl: int = GridData.get_highest_floor(cell)
		for offset in NEIGHBOR_OFFSETS:
			var neighbor: Vector2i = cell + offset
			if not GridData.has_any_tile(neighbor):
				void_cells[neighbor] = maxi(void_cells.get(neighbor, 0), cell_fl)

	if void_cells.is_empty():
		return

	# 4. 找到需要生成的最大楼层
	var max_all_floors := 0
	for void_cell in void_cells.keys():
		max_all_floors = maxi(max_all_floors, void_cells[void_cell])

	# 5. 为每个楼层创建独立的 StaticBody2D，绑定该楼层专用的物理碰撞层
	# 彻底杜绝低层空气墙意外阻挡高层角色，或高层空气墙意外阻挡低层角色！
	var floor_bodies: Dictionary = {}
	for fl in range(max_all_floors + 1):
		var body := StaticBody2D.new()
		body.name = "AirWall_Floor%d" % fl
		body.collision_layer = GridData.get_floor_collision_layer(fl)
		body.collision_mask = 0
		body.add_to_group("air_walls")
		add_child(body)
		floor_bodies[fl] = body

	# 6. 为每一个虚空格按相邻楼层在对应楼层的 StaticBody2D 下生成菱形碰撞体
	for void_cell in void_cells.keys():
		var max_fl: int = void_cells[void_cell]
		var center := GridData.cell_to_world(void_cell)
		for fl in range(max_fl + 1):
			var body: StaticBody2D = floor_bodies[fl]
			var col := CollisionPolygon2D.new()
			col.position = center + Vector2(0.0, GridData.get_floor_pixel_offset(fl))
			col.polygon = DIAMOND_POINTS
			body.add_child(col)