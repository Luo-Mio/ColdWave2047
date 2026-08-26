# grid_data.gd —— 全局高度场数据(Autoload 单例 GridData)
extends Node

const FLOOR_HEIGHT: float = 8.0   # 每层视觉高度差

# 高度场:grid[Vector3i(x,y,z)] = true 表示该格该层有砖
var grid: Dictionary = {}
# 所有 TileMapLayer 引用,从低到高
var layers: Array[TileMapLayer] = []

# 遍历所有层,生成高度场
func build_from_layers(layer_nodes: Array[TileMapLayer]) -> void:
	layers = layer_nodes
	grid.clear()
	for z in layers.size():
		for cell in layers[z].get_used_cells():
			grid[Vector3i(cell.x, cell.y, z)] = true

# 世界坐标 → 格子坐标
func world_to_cell(world_pos: Vector2) -> Vector2i:
	if layers.is_empty():
		return Vector2i.ZERO
	return layers[0].local_to_map(layers[0].to_local(world_pos))

# 【排序核心】格子 → 排序键(该格基底屏幕 y)
# 排序只问"这个格在哪一行",不问高度 → 谁更靠南谁后画
func cell_to_sort_key(cell: Vector2i) -> float:
	if layers.is_empty():
		return 0.0
	var half_h := layers[0].tile_set.tile_size.y / 2.0
	var row := float(cell.x + cell.y)
	var col := float(cell.x - cell.y)
	# 主键 = 行(深度);微调 = 列:
	# 同行时,靠东(列大)的键更小 → 先画 → 被西边的砖盖(正确遮挡)
	return row * half_h - col * 0.001

# 某格最高的有砖楼层(后面做移动/高度要用)
func get_highest_floor(cell: Vector2i) -> int:
	for z in range(layers.size() - 1, -1, -1):
		if grid.has(Vector3i(cell.x, cell.y, z)):
			return z
	return 0

# 楼层号 → Y 像素偏移(后面做角色高度要用)
func get_floor_pixel_offset(floor: int) -> float:
	return -float(floor + 1) * FLOOR_HEIGHT
