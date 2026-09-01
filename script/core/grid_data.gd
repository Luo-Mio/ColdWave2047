# grid_data.gd —— 全局高度场与 4x4 微网格数据核心(Autoload 单例 GridData)
extends Node

const FLOOR_HEIGHT: float = 16.0   # 每层视觉高度差

# 1. 地形高度场数据
var grid: Dictionary = {}
var layers: Array[TileMapLayer] = []
var tile_cells: Dictionary = {}
var highest_floor: Dictionary = {}
# 2. 物体与农作物占用表
# 大物体占用表(4x4整格,如树木): key = cell_key(cell), value = 物体节点
var objects_at: Dictionary = {}
# 微物体占用表(1x1小麦/2x2灌木): key = sub_slot_key(cell, sub_pos), value = 作物节点
var sub_objects_at: Dictionary = {}

# 遍历所有层,生成高度场
func build_from_layers(layer_nodes: Array[TileMapLayer]) -> void:
	layers = layer_nodes
	grid.clear()
	tile_cells.clear()
	highest_floor.clear() # ← 清空缓存
	for z in layers.size():
		for cell in layers[z].get_used_cells():
			var k := cell_key(cell)
			grid[Vector3i(cell.x, cell.y, z)] = true
			tile_cells[k] = true
			highest_floor[k] = maxi(highest_floor.get(k, 0), z) # ← 记录该格最高层

# 世界坐标 → 大格子坐标
func world_to_cell(world_pos: Vector2) -> Vector2i:
	if layers.is_empty():
		return Vector2i.ZERO
	return layers[0].local_to_map(layers[0].to_local(world_pos))

# 大格子坐标 → 大格子中心的世界坐标
func cell_to_world(cell: Vector2i) -> Vector2:
	if layers.is_empty():
		return Vector2.ZERO
	return layers[0].map_to_local(cell)

# 【4x4 微网格核心算法】给定大格内 (0~3, 0~3) 子格及物体大小，计算出世界相对偏移像素
func sub_cell_to_local_offset(sub_cell: Vector2i, size: Vector2i = Vector2i(1, 1)) -> Vector2:
	var center_u := float(sub_cell.x) + float(size.x) * 0.5 - 2.0
	var center_v := float(sub_cell.y) + float(size.y) * 0.5 - 2.0
	# 64x32 对应的 4x4 微格基向量为 (8, 4) 与 (-8, 4)
	var offset_x := (center_u - center_v) * 8.0  # 原本是 4.0
	var offset_y := (center_u + center_v) * 4.0  # 原本是 2.0
	return Vector2(offset_x, offset_y).round()

# 给定鼠标世界坐标和大格，反算出鼠标当前指向 16 个小格中的哪一个 (0~3, 0~3)
func world_to_sub_cell(world_pos: Vector2, cell: Vector2i) -> Vector2i:
	var cell_center := cell_to_world(cell) + Vector2(0.0, get_floor_pixel_offset(get_highest_floor(cell)))
	var rel := world_pos - cell_center
	var u := (rel.x / 8.0 + rel.y / 4.0) * 0.5   # 4.0 改为 8.0, 2.0 改为 4.0
	var v := (rel.y / 4.0 - rel.x / 8.0) * 0.5   # 2.0 改为 4.0, 4.0 改为 8.0
	var sx := clampi(int(floor(u + 2.0)), 0, 3)
	var sy := clampi(int(floor(v + 2.0)), 0, 3)
	return Vector2i(sx, sy)

# 【排序核心】格子 → 排序键
func cell_to_sort_key(cell: Vector2i) -> float:
	if layers.is_empty():
		return 0.0
	var half_h := layers[0].tile_set.tile_size.y / 2.0
	var row := float(cell.x + cell.y)
	var col := float(cell.x - cell.y)
	return row * half_h - col * 0.001

# 某格最高楼层（O(1) 瞬时查询，零循环零垃圾）
func get_highest_floor(cell: Vector2i) -> int:
	return highest_floor.get(cell_key(cell), 0)
	
# 楼层号 → Y 像素偏移
func get_floor_pixel_offset(floor: int) -> float:
	return -float(floor + 1) * FLOOR_HEIGHT

# 某格是否有砖
func has_any_tile(cell: Vector2i) -> bool:
	return tile_cells.has(cell_key(cell))

# 键编码
func cell_key(cell: Vector2i) -> int:
	return (cell.x + 500) * 10000 + (cell.y + 500)

func sub_slot_key(cell: Vector2i, sub_pos: Vector2i) -> int:
	return cell_key(cell) * 16 + (sub_pos.y * 4 + sub_pos.x)

# 砖块增删
func set_tile(cell: Vector2i, z: int, exists: bool) -> void:
	var key := Vector3i(cell.x, cell.y, z)
	var ck := cell_key(cell)
	if exists:
		grid[key] = true
		tile_cells[ck] = true
		highest_floor[ck] = maxi(highest_floor.get(ck, 0), z)
	else:
		grid.erase(key)
		# 拆除时重新计算该格的最高楼层
		var max_z := 0
		var has_any := false
		for zz in range(z, -1, -1):
			if grid.has(Vector3i(cell.x, cell.y, zz)):
				max_z = zz
				has_any = true
				break
		if has_any:
			highest_floor[ck] = max_z
		else:
			highest_floor.erase(ck)
			tile_cells.erase(ck)

# === 物体与农作物多槽位占用系统 ===

# 查询指定位置是否已被占用（支持 1x1 小麦、2x2 灌木、4x4 大树）
func is_slot_occupied(cell: Vector2i, sub_pos: Vector2i = Vector2i.ZERO, size: Vector2i = Vector2i(1, 1)) -> bool:
	# 1. 如果有整格大物体(大树)，直接判定为全部占用
	if objects_at.has(cell_key(cell)):
		return true
	# 2. 如果要放 4x4 大物体，检查该格是否有任何小麦/微物体
	if size == Vector2i(4, 4):
		for y in 4:
			for x in 4:
				if sub_objects_at.has(sub_slot_key(cell, Vector2i(x, y))):
					return true
		return false
	# 3. 检查指定的微槽位是否已有物体
	for dy in range(size.y):
		for dx in range(size.x):
			var sp := sub_pos + Vector2i(dx, dy)
			if sp.x > 3 or sp.y > 3:
				return true # 超出边界
			if sub_objects_at.has(sub_slot_key(cell, sp)):
				return true
	return false

# 注册物体
func register_object(cell: Vector2i, obj: Node, sub_pos: Vector2i = Vector2i.ZERO, size: Vector2i = Vector2i(4, 4)) -> void:
	if size == Vector2i(4, 4):
		objects_at[cell_key(cell)] = obj
	else:
		for dy in range(size.y):
			for dx in range(size.x):
				var sp := sub_pos + Vector2i(dx, dy)
				sub_objects_at[sub_slot_key(cell, sp)] = obj

# 取消注册
func unregister_object(cell: Vector2i, sub_pos: Vector2i = Vector2i.ZERO, size: Vector2i = Vector2i(4, 4)) -> void:
	if size == Vector2i(4, 4):
		objects_at.erase(cell_key(cell))
	else:
		for dy in range(size.y):
			for dx in range(size.x):
				var sp := sub_pos + Vector2i(dx, dy)
				sub_objects_at.erase(sub_slot_key(cell, sp))

# 获取某格子具体位置的物体
func get_object_at(cell: Vector2i, sub_pos: Vector2i = Vector2i.ZERO) -> Node:
	if objects_at.has(cell_key(cell)):
		return objects_at[cell_key(cell)]
	if sub_objects_at.has(sub_slot_key(cell, sub_pos)):
		return sub_objects_at[sub_slot_key(cell, sub_pos)]
	return null

# 获取某格全部 16 个微槽位的占用布尔数组（供几何网格渲染器快速画图）
func get_cell_sub_occupancies(cell: Vector2i) -> Array[bool]:
	var mask: Array[bool] = []
	mask.resize(16)
	var has_full: bool = objects_at.has(cell_key(cell))
	for y in 4:
		for x in 4:
			var idx := y * 4 + x
			if has_full or sub_objects_at.has(sub_slot_key(cell, Vector2i(x, y))):
				mask[idx] = true
			else:
				mask[idx] = false
	return mask

# 兼容旧接口
func has_object(cell: Vector2i) -> bool:
	return is_slot_occupied(cell, Vector2i.ZERO, Vector2i(4, 4))


# 获取某格子上存在的所有物体（整格大树 + 所有微格植物，去重返回列表）
func get_all_objects_at(cell: Vector2i) -> Array[Node]:
	var list: Array[Node] = []
	var ck := cell_key(cell)
	if objects_at.has(ck):
		list.append(objects_at[ck])
	for y in 4:
		for x in 4:
			var k := sub_slot_key(cell, Vector2i(x, y))
			if sub_objects_at.has(k):
				var obj: Node = sub_objects_at[k]
				if not list.has(obj):
					list.append(obj)
	return list