# grid_data.gd —— 全局平面网格与 4x4 微网格空间管理核心 (Autoload 单例 GridData)
extends Node

const TILE_WIDTH: float = 64.0
const TILE_HEIGHT: float = 32.0

var ground_layer: TileMapLayer = null

# 物体与微格占用字典
# 4x4 整格物体表 (如大树): key = cell (Vector2i), value = Node
var objects_at: Dictionary = {}
# 1x1 或 2x2 微物体表 (如小麦、灌木): key = Vector3i(cell.x, cell.y, sub_y * 4 + sub_x), value = Node
var sub_objects_at: Dictionary = {}

## 注册主场景的基层 TileMapLayer
func register_ground_layer(layer: TileMapLayer) -> void:
	ground_layer = layer

## 世界坐标 -> 大格坐标 (Vector2i)
func world_to_cell(world_pos: Vector2) -> Vector2i:
	if ground_layer:
		return ground_layer.local_to_map(ground_layer.to_local(world_pos))
	# 备用几何换算 (2:1 等距菱形标准公式)
	var u := (world_pos.x / 32.0 + world_pos.y / 16.0) * 0.5
	var v := (world_pos.y / 16.0 - world_pos.x / 32.0) * 0.5
	return Vector2i(int(floor(u)), int(floor(v)))

## 大格坐标 -> 格子中心世界坐标
func cell_to_world(cell: Vector2i) -> Vector2:
	if ground_layer:
		return ground_layer.map_to_local(cell) + ground_layer.position
	return Vector2((cell.x - cell.y) * 32.0, (cell.x + cell.y) * 16.0 + 16.0)

## 检查某格是否有地面地砖
func has_ground_tile(cell: Vector2i) -> bool:
	if ground_layer:
		return ground_layer.get_cell_source_id(cell) != -1
	return true

## 获取指定图集源的所有可用瓦片坐标列表 (遍历 TileSetAtlasSource 所有定义的变种)
func get_tile_variant_coords(source_id: int = 0) -> Array[Vector2i]:
	var list: Array[Vector2i] = []
	if ground_layer and ground_layer.tile_set:
		var source := ground_layer.tile_set.get_source(source_id) as TileSetAtlasSource
		if source:
			for i in source.get_tiles_count():
				list.append(source.get_tile_id(i))
	return list

## 获取随机一个瓷砖变种坐标 (无论未来增加多少行多少列均自动支持)
func get_random_tile_coords(source_id: int = 0) -> Vector2i:
	var variants := get_tile_variant_coords(source_id)
	if not variants.is_empty():
		return variants[randi() % variants.size()]
	return Vector2i.ZERO

## 【4x4 微网格核心算法】给定大格内 (0~3, 0~3) 子格及物体尺寸，计算出世界相对偏移像素
func sub_cell_to_local_offset(sub_cell: Vector2i, size: Vector2i = Vector2i(1, 1)) -> Vector2:
	var center_u := float(sub_cell.x) + float(size.x) * 0.5 - 2.0
	var center_v := float(sub_cell.y) + float(size.y) * 0.5 - 2.0
	var offset_x := (center_u - center_v) * 8.0
	var offset_y := (center_u + center_v) * 4.0
	return Vector2(offset_x, offset_y).round()

## 给定鼠标世界坐标和大格，反算出鼠标当前指向 16 个小格中的哪一个 (0~3, 0~3)
func world_to_sub_cell(world_pos: Vector2, cell: Vector2i) -> Vector2i:
	var cell_center := cell_to_world(cell)
	var rel := world_pos - cell_center
	var u := (rel.x / 8.0 + rel.y / 4.0) * 0.5
	var v := (rel.y / 4.0 - rel.x / 8.0) * 0.5
	var sx := clampi(int(floor(u + 2.0)), 0, 3)
	var sy := clampi(int(floor(v + 2.0)), 0, 3)
	return Vector2i(sx, sy)

## 生成微槽位唯一 key
func _sub_slot_key(cell: Vector2i, sub_pos: Vector2i) -> Vector3i:
	return Vector3i(cell.x, cell.y, sub_pos.y * 4 + sub_pos.x)

## 检查指定槽位是否已被占用
func is_slot_occupied(cell: Vector2i, sub_pos: Vector2i = Vector2i.ZERO, size: Vector2i = Vector2i(4, 4)) -> bool:
	# 1. 如果该大格存在 4x4 整格物体，直接视为占满
	if objects_at.has(cell):
		return true
	# 2. 如果企图放置 4x4 整格物体，只要本格内有任何微物体，视为冲突
	if size == Vector2i(4, 4):
		for dy in 4:
			for dx in 4:
				if sub_objects_at.has(_sub_slot_key(cell, Vector2i(dx, dy))):
					return true
		return false
	# 3. 针对 1x1 或 2x2 微物体，检查对应跨度的每个微槽位
	for dy in range(size.y):
		for dx in range(size.x):
			var sp := sub_pos + Vector2i(dx, dy)
			if sub_objects_at.has(_sub_slot_key(cell, sp)):
				return true
	return false

## 登记物体占用 (支持记录变体编号)
func register_object(cell: Vector2i, obj: Node, sub_pos: Vector2i = Vector2i.ZERO, size: Vector2i = Vector2i(4, 4), item_id: String = "", variant_idx: int = -1) -> void:
	if obj:
		obj.set_meta("cell", cell)
		obj.set_meta("sub_cell", sub_pos)
		obj.set_meta("grid_size", size)
		if not item_id.is_empty():
			obj.set_meta("item_id", item_id)
		if variant_idx >= 0:
			obj.set_meta("variant", variant_idx)
		elif obj.has_method("get_variant"):
			obj.set_meta("variant", obj.call("get_variant"))

	if size == Vector2i(4, 4):
		objects_at[cell] = obj
	else:
		for dy in range(size.y):
			for dx in range(size.x):
				var sp := sub_pos + Vector2i(dx, dy)
				sub_objects_at[_sub_slot_key(cell, sp)] = obj

## 注销物体占用
func unregister_object(cell: Vector2i, sub_pos: Vector2i = Vector2i.ZERO, size: Vector2i = Vector2i(4, 4)) -> void:
	if size == Vector2i(4, 4):
		objects_at.erase(cell)
	else:
		for dy in range(size.y):
			for dx in range(size.x):
				var sp := sub_pos + Vector2i(dx, dy)
				sub_objects_at.erase(_sub_slot_key(cell, sp))

## 获取所有已放置物体的详细信息列表 (供保存地图与查询使用)
func get_all_placed_objects() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}

	for cell in objects_at:
		var node: Node = objects_at[cell]
		if is_instance_valid(node) and not seen.has(node):
			seen[node] = true
			var var_idx: int = node.call("get_variant") if node.has_method("get_variant") else int(node.get_meta("variant", 0))
			result.append({
				"id": node.get_meta("item_id", ""),
				"cell": cell,
				"sub_cell": node.get_meta("sub_cell", Vector2i.ZERO),
				"grid_size": node.get_meta("grid_size", Vector2i(4, 4)),
				"variant": var_idx,
				"node": node
			})

	for key in sub_objects_at:
		var node: Node = sub_objects_at[key]
		if is_instance_valid(node) and not seen.has(node):
			seen[node] = true
			var var_idx: int = node.call("get_variant") if node.has_method("get_variant") else int(node.get_meta("variant", 0))
			result.append({
				"id": node.get_meta("item_id", ""),
				"cell": node.get_meta("cell", Vector2i(key.x, key.y)),
				"sub_cell": node.get_meta("sub_cell", Vector2i(key.z % 4, int(key.z / 4))),
				"grid_size": node.get_meta("grid_size", Vector2i(1, 1)),
				"variant": var_idx,
				"node": node
			})
	return result

## 清空所有已登记的物体数据
func clear_all_objects() -> void:
	objects_at.clear()
	sub_objects_at.clear()

## 获取指定槽位的物体节点
func get_object_at(cell: Vector2i, sub_pos: Vector2i = Vector2i.ZERO) -> Node:
	if objects_at.has(cell):
		return objects_at[cell]
	var k := _sub_slot_key(cell, sub_pos)
	if sub_objects_at.has(k):
		return sub_objects_at[k]
	return null

## 获取大格内全部 16 个微槽位的占用布尔数组 (供 Selector 绘制小绿点和小红点)
func get_cell_sub_occupancies(cell: Vector2i) -> Array[bool]:
	var mask: Array[bool] = []
	mask.resize(16)
	var has_full: bool = objects_at.has(cell)
	for y in 4:
		for x in 4:
			var idx := y * 4 + x
			if has_full or sub_objects_at.has(_sub_slot_key(cell, Vector2i(x, y))):
				mask[idx] = true
			else:
				mask[idx] = false
	return mask

## 扫描并自动登记场景中已存在的预置物体 (无论是编辑器手动摆放的还是地图载入后保存的)
func scan_and_register_existing_entities(container: Node2D) -> int:
	if container == null:
		return 0

	var count := 0
	for child in container.get_children():
		if not (child is Node2D):
			continue
		if child.is_in_group("player"):
			continue

		var cell := Vector2i(-99999, -99999)
		var sub_cell := Vector2i.ZERO
		var grid_size := Vector2i(4, 4)
		var item_id := ""

		# 1. 优先读取持久化元数据 (由地图系统载入并保存到场景中的实体)
		if child.has_meta("cell"):
			cell = child.get_meta("cell")
			sub_cell = child.get_meta("sub_cell", Vector2i.ZERO)
			grid_size = child.get_meta("grid_size", Vector2i(4, 4))
			item_id = child.get_meta("item_id", "")
		else:
			# 2. 启发式自动推导 (适用于策划直接在编辑器中拖入场景摆放的实体)
			var node_name := child.name.to_lower()
			if node_name.contains("wheat") or node_name.contains("plant"):
				grid_size = Vector2i(1, 1)
				cell = world_to_cell(child.position)
				sub_cell = world_to_sub_cell(child.position, cell)
				item_id = "wheat"
			else:
				# 默认大物体 (树木、建筑等 4x4)
				grid_size = Vector2i(4, 4)
				cell = world_to_cell(child.position)
				sub_cell = Vector2i.ZERO
				if node_name.contains("birch") or node_name.contains("britch"):
					item_id = "birch_tree"
				elif node_name.contains("oak") or node_name.contains("autumn"):
					item_id = "oak_tree"

		if cell != Vector2i(-99999, -99999):
			var var_idx: int = -1
			if child.has_meta("variant"):
				var_idx = int(child.get_meta("variant"))
			elif child.has_method("get_variant"):
				var_idx = child.call("get_variant")
			register_object(cell, child, sub_cell, grid_size, item_id, var_idx)
			count += 1

	if count > 0:
		print("[GridData] 场景初始化已自动扫描并登记 %d 个预置物体占用！" % count)
	return count

