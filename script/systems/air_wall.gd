# air_wall.gd —— 全自动地图边缘虚空空气墙生成器
class_name AirWallManager
extends StaticBody2D

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
	# 设置物理碰撞层（Layer 2：障碍物层，匹配角色的 collision_mask）
	collision_layer = 2
	collision_mask = 0

# 全自动重建边缘空气墙
func rebuild_walls() -> void:
	# 1. 清理现有的碰撞形状
	for child in get_children():
		child.queue_free()

	if GridData.layers.is_empty():
		return

	# 2. 从第 0 层直接获取标准的 Vector2i 地面坐标列表
	var used_cells: Array[Vector2i] = GridData.layers[0].get_used_cells()
	if used_cells.is_empty():
		return

	# 3. 收集所有“紧邻地面的空白虚空格”（用字典去重）
	var void_cells: Dictionary = {}
	for cell in used_cells:
		for offset in NEIGHBOR_OFFSETS:
			var neighbor: Vector2i = cell + offset
			# 如果该相邻格完全没有瓷砖，说明它是虚空边界
			if not GridData.has_any_tile(neighbor):
				void_cells[neighbor] = true

	# 4. 为每一个虚空格生成 32x16 菱形物理碰撞体
	for void_cell in void_cells.keys():
		var center := GridData.cell_to_world(void_cell)
		var col := CollisionPolygon2D.new()
		col.position = center
		col.polygon = DIAMOND_POINTS
		add_child(col)