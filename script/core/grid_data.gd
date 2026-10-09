# grid_data.gd —— 全局高度场与 4x4 微网格数据核心(Autoload 单例 GridData)
extends Node

const FLOOR_HEIGHT: float = 16.0   # 每层视觉高度差

# 1. 地形高度场数据
var grid: Dictionary = {}
var layers: Array[TileMapLayer] = []
var tile_cells: Dictionary = {}
var highest_floor: Dictionary = {}

# 2.5D GPU 高度场纹理 (R8 格式, 256x256, 覆盖 [-128, 128] 网格, 供 3D 视线步进 Shader 使用)
const HEIGHT_MAP_WIDTH: int = 256
const HEIGHT_MAP_HEIGHT: int = 256
const HEIGHT_MAP_OFFSET: Vector2i = Vector2i(128, 128)
var height_map_image: Image = null
var height_map_texture: ImageTexture = null

# 2. 物体与农作物占用表
# 大物体占用表(4x4整格,如树木): key = cell_key(cell), value = 物体节点
var objects_at: Dictionary = {}
# 微物体占用表(1x1小麦/2x2灌木): key = sub_slot_key(cell, sub_pos), value = 作物节点
var sub_objects_at: Dictionary = {}

# 3. 地表覆盖数据 (草皮/菌毯/积雪等): key = Vector3i(cell.x, cell.y, z), value = surf_type (例如 "grass", "creep", "snow")
var surf_grid: Dictionary = {}
var turf_grid: Dictionary:
	get: return surf_grid
	set(v): surf_grid = v

# === 2.5D 顶层落差边缘标记系统 (Edge Indicator) ===
const EDGE_NONE: int = 0
const EDGE_TIP_L: int = 1
const EDGE_TIP_M: int = 2
const EDGE_TIP_R: int = 3

signal edge_changed(cell: Vector2i, edge_type: int, new_floor: int, old_floor: int)

# 顶层边缘标记缓存: cell (Vector2i) -> edge_type (int)
var edge_grid: Dictionary = {}
# 顶层边缘对应楼层高度缓存: cell (Vector2i) -> z (int)
var edge_floor: Dictionary = {}

# === 2.5D 多楼层物理碰撞分层系统 ===
# Layer 1 (bit 0): 地形 / 空气墙边界
# Layer 2 (bit 1): 全局基础障碍 / 边缘碰撞
# Layer 3 (bit 2): 角色生物层 (CharacterBody2D)
# Layer 4 (bit 3): 掉落物 / 道具拾取 (Item pickup)
# Layer 5~24 (bit 4~23): 对应 0~19 楼层物体专属碰撞层，彻底杜绝跨楼层碰撞穿透！
const BASE_OBJECT_LAYER_BIT: int = 4

# 获取指定楼层物体专用的物理碰撞层 (1 << (4 + floor))
func get_floor_collision_layer(floor_idx: int) -> int:
	return 1 << clampi(BASE_OBJECT_LAYER_BIT + floor_idx, 0, 31)

# 获取实体在指定楼层应当监听的物理碰撞掩码 (基础层 + 同楼层物体层)
func get_entity_collision_mask_for_floor(floor_idx: int, base_mask: int = 6) -> int:
	return (base_mask & ~get_all_floors_object_mask()) | get_floor_collision_layer(floor_idx)

# 获取所有楼层物体碰撞层的全局掩码 (用于迷雾/阴影全局射线检测)
func get_all_floors_object_mask(max_floors: int = 20) -> int:
	var mask := 0
	for f in range(max_floors):
		mask |= (1 << clampi(BASE_OBJECT_LAYER_BIT + f, 0, 31))
	return mask

func has_surf(cell: Vector2i, z: int) -> bool:
	return surf_grid.has(Vector3i(cell.x, cell.y, z))

func has_turf(cell: Vector2i, z: int) -> bool:
	return has_surf(cell, z)

func get_surf(cell: Vector2i, z: int) -> String:
	return surf_grid.get(Vector3i(cell.x, cell.y, z), "")

func set_surf(cell: Vector2i, z: int, exists: bool, type: String = "grass") -> void:
	var key := Vector3i(cell.x, cell.y, z)
	if exists:
		surf_grid[key] = type
	else:
		surf_grid.erase(key)

func set_turf(cell: Vector2i, z: int, exists: bool) -> void:
	set_surf(cell, z, exists, "grass")

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
	_update_height_map()
	rebuild_edge_map()

# 世界坐标 → 大格子坐标
func world_to_cell(world_pos: Vector2) -> Vector2i:
	if layers.is_empty():
		return Vector2i.ZERO
	return layers[0].local_to_map(layers[0].to_local(world_pos))

# 大格子坐标 → 大格子中心的世界坐标
func cell_to_world(cell: Vector2i) -> Vector2:
	if layers.is_empty():
		return Vector2.ZERO
	return layers[0].map_to_local(cell) + layers[0].position

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

# 【排序核心】格子 → 排序键 (基于交错等距网格视觉屏幕深度 row = cell.y)
func cell_to_sort_key(cell: Vector2i) -> float:
	if layers.is_empty():
		return 0.0
	var half_h := layers[0].tile_set.tile_size.y / 2.0
	var row := float(cell.y)
	var col := float(cell.x)
	return row * half_h - col * 0.001

# 某格最高楼层（O(1) 瞬时查询，零循环零垃圾）
func get_highest_floor(cell: Vector2i) -> int:
	return highest_floor.get(cell_key(cell), 0)
	
# 楼层号 → Y 像素偏移 (0层=0px, 1层=-16px, 2层=-32px)
func get_floor_pixel_offset(floor: int) -> float:
	return -float(floor) * FLOOR_HEIGHT

# 某格是否有砖
func has_any_tile(cell: Vector2i) -> bool:
	return tile_cells.has(cell_key(cell))

# 某格在指定楼层 z 是否有砖
func has_tile(cell: Vector2i, z: int) -> bool:
	return grid.has(Vector3i(cell.x, cell.y, z))

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
		surf_grid.erase(key)
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

	if height_map_image != null:
		var cx := cell.x + HEIGHT_MAP_OFFSET.x
		var cy := cell.y + HEIGHT_MAP_OFFSET.y
		if cx >= 0 and cx < HEIGHT_MAP_WIDTH and cy >= 0 and cy < HEIGHT_MAP_HEIGHT:
			var fl: int = highest_floor.get(ck, 0)
			height_map_image.set_pixel(cx, cy, Color(float(fl) / 16.0, 0, 0, 1))
			if height_map_texture != null:
				height_map_texture.update(height_map_image)

	update_edges_around(cell)

# 初始化并全量刷新全局 2.5D 高度场纹理 (ImageTexture R8)
func _update_height_map() -> void:
	if height_map_image == null:
		height_map_image = Image.create(HEIGHT_MAP_WIDTH, HEIGHT_MAP_HEIGHT, false, Image.FORMAT_R8)
	else:
		height_map_image.fill(Color(0, 0, 0, 1))

	for z in layers.size():
		for cell in layers[z].get_used_cells():
			var cx := cell.x + HEIGHT_MAP_OFFSET.x
			var cy := cell.y + HEIGHT_MAP_OFFSET.y
			if cx >= 0 and cx < HEIGHT_MAP_WIDTH and cy >= 0 and cy < HEIGHT_MAP_HEIGHT:
				var current_px := height_map_image.get_pixel(cx, cy)
				var current_fl := int(round(current_px.r * 16.0))
				if z > current_fl:
					height_map_image.set_pixel(cx, cy, Color(float(z) / 16.0, 0, 0, 1))

	if height_map_texture == null:
		height_map_texture = ImageTexture.create_from_image(height_map_image)
	else:
		height_map_texture.update(height_map_image)

# 获取全局 2.5D 高度场纹理 (供战争迷雾与视线 Shader 采样)
func get_height_map_texture() -> ImageTexture:
	if height_map_texture == null:
		_update_height_map()
	return height_map_texture


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


# === 2.5D 顶层落差边缘标记计算与拓扑维护 (Edge Indicator) ===

# 获取某格当前的边缘标记类型 (EDGE_NONE / EDGE_TIP_L / EDGE_TIP_M / EDGE_TIP_R)
func get_edge(cell: Vector2i) -> int:
	return edge_grid.get(cell, EDGE_NONE)

func get_edge_floor(cell: Vector2i) -> int:
	return edge_floor.get(cell, -1)

# 精确获取 2.5D 等距堆叠网格斜上方与斜下方相邻格（严格区分奇偶行）
func get_nw_neighbor(cell: Vector2i) -> Vector2i:
	var is_odd := (absi(cell.y) % 2 == 1)
	return Vector2i(cell.x, cell.y - 1) if is_odd else Vector2i(cell.x - 1, cell.y - 1)

func get_ne_neighbor(cell: Vector2i) -> Vector2i:
	var is_odd := (absi(cell.y) % 2 == 1)
	return Vector2i(cell.x + 1, cell.y - 1) if is_odd else Vector2i(cell.x, cell.y - 1)

func get_se_neighbor(cell: Vector2i) -> Vector2i:
	var is_odd := (absi(cell.y) % 2 == 1)
	return Vector2i(cell.x + 1, cell.y + 1) if is_odd else Vector2i(cell.x, cell.y + 1)

func get_sw_neighbor(cell: Vector2i) -> Vector2i:
	var is_odd := (absi(cell.y) % 2 == 1)
	return Vector2i(cell.x, cell.y + 1) if is_odd else Vector2i(cell.x - 1, cell.y + 1)

# 计算指定格子当前的边缘形态（纯函数计算）
func compute_edge_at(cell: Vector2i) -> int:
	if not has_any_tile(cell):
		return EDGE_NONE
	var z := get_highest_floor(cell)
	var nw := get_nw_neighbor(cell)
	var ne := get_ne_neighbor(cell)
	var z_nw := get_highest_floor(nw) if has_any_tile(nw) else -1
	var z_ne := get_highest_floor(ne) if has_any_tile(ne) else -1
	var expose_left := (z_nw < z)
	var expose_right := (z_ne < z)
	if expose_left and expose_right:
		return EDGE_TIP_M
	elif expose_left:
		return EDGE_TIP_L
	elif expose_right:
		return EDGE_TIP_R
	return EDGE_NONE

# 更新单个格子的边缘缓存并触发信号 (若状态或楼层改变)
func update_edge_at(cell: Vector2i) -> bool:
	var old_type: int = edge_grid.get(cell, EDGE_NONE)
	var old_z: int = edge_floor.get(cell, -1)

	var has_tile_now: bool = has_any_tile(cell)
	var new_z: int = get_highest_floor(cell) if has_tile_now else -1
	var new_type: int = compute_edge_at(cell) if has_tile_now else EDGE_NONE

	if old_type != new_type or old_z != new_z:
		if new_type == EDGE_NONE or new_z < 0:
			edge_grid.erase(cell)
			edge_floor.erase(cell)
		else:
			edge_grid[cell] = new_type
			edge_floor[cell] = new_z

		edge_changed.emit(cell, new_type, new_z, old_z)
		return true
	return false

# 当某格地砖发生变动时，联动刷新本格及四周物理相邻格
func update_edges_around(cell: Vector2i) -> void:
	update_edge_at(cell)
	update_edge_at(get_se_neighbor(cell))
	update_edge_at(get_sw_neighbor(cell))
	update_edge_at(get_nw_neighbor(cell))
	update_edge_at(get_ne_neighbor(cell))

# 全量构建所有地块的边缘缓存
func rebuild_edge_map() -> void:
	edge_grid.clear()
	edge_floor.clear()
	var processed: Dictionary = {}
	for k in grid.keys():
		var cell := Vector2i(k.x, k.y)
		if not processed.has(cell):
			processed[cell] = true
			var edge := compute_edge_at(cell)
			if edge != EDGE_NONE:
				edge_grid[cell] = edge
				edge_floor[cell] = get_highest_floor(cell)