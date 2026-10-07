# turf_system.gd —— 2.5D 双网格表面草皮系统 (Dual-Grid Turf System)
class_name TurfSystem
extends Node

static var instance: TurfSystem = null

# 16 种双网格角落组合对应的瓦片坐标映射表 (遵循 4-bit 掩码 0~15，完全匹配 grass_out.png)
# Bit 0: 上角 (Top), Bit 1: 右角 (Right), Bit 2: 左角 (Left), Bit 3: 下角 (Bottom)
const MASK_TO_ATLAS: Array[Vector2i] = [
	Vector2i(0, 3), # 0:  0000 (完全透明/无草)
	Vector2i(3, 3), # 1:  0001 (仅上角有草)
	Vector2i(0, 2), # 2:  0010 (仅右角有草)
	Vector2i(1, 2), # 3:  0011 (上 + 右)
	Vector2i(0, 0), # 4:  0100 (仅左角有草)
	Vector2i(3, 2), # 5:  0101 (上 + 左)
	Vector2i(2, 3), # 6:  0110 (右 + 左)
	Vector2i(3, 1), # 7:  0111 (上 + 右 + 左)
	Vector2i(1, 3), # 8:  1000 (仅下角有草)
	Vector2i(0, 1), # 9:  1001 (上 + 下)
	Vector2i(1, 0), # 10: 1010 (右 + 下)
	Vector2i(2, 2), # 11: 1011 (上 + 右 + 下)
	Vector2i(3, 0), # 12: 1100 (左 + 下)
	Vector2i(2, 0), # 13: 1101 (上 + 左 + 下)
	Vector2i(1, 1), # 14: 1110 (右 + 左 + 下)
	Vector2i(2, 1), # 15: 1111 (4角全满，完整草皮)
]

# 编辑器中手动绘制草皮时的占位图块坐标（第3列第2行，满草图块）
const PLACEHOLDER_TILE: Vector2i = Vector2i(2, 1)

var grass_tileset: TileSet = preload("res://resources/surface/GreenGrass/grass_tileset.tres")
var cell_script: GDScript = preload("res://script/core/row_layer.gd")

var sort_world: Node2D = null
var layers_node: Node2D = null
var floor0_turf_layer: TileMapLayer = null

func _init() -> void:
	instance = self

# 初始化双网格草皮系统（在 main_scene._ready() 中调用）
func init_turf_system(main_scene: Node2D, sort_world_ref: Node2D, layers_ref: Node2D) -> void:
	instance = self
	sort_world = sort_world_ref
	layers_node = layers_ref

	# 1. 扫描场景中由关卡设计师在编辑器里手动绘制的草皮占位层
	_scan_editor_turf_layers(main_scene)

	# 2. 准备第 0 层平坦地表的双网格专用渲染层（作为底板并入 layers）
	_setup_floor0_turf_layer()

	# 3. 初始全量烘焙：把所有占位图转换为带圆角与平滑边缘的双网格切片
	rebuild_all_turf()

# 扫描并解析编辑器中绘制的草皮图层（提取占位图块数据存入 GridData）
func _scan_editor_turf_layers(main_scene: Node2D) -> void:
	# 收集所有名称包含 "turf" 的 TileMapLayer
	var scanned_layers: Array[TileMapLayer] = []
	for node in main_scene.find_children("*", "TileMapLayer", true, false):
		if node is TileMapLayer and node.name.to_lower().contains("turf"):
			scanned_layers.append(node)

	for tl in scanned_layers:
		# 推导楼层高度 z
		var z := 0
		var num_str := ""
		var layer_name := str(tl.name)
		for ch in layer_name:
			if ch >= "0" and ch <= "9":
				num_str += ch
		if num_str != "":
			# 如果命名是 turf1 对应 z=0，turf2 对应 z=1
			var num := num_str.to_int()
			z = num - 1 if num > 0 else 0
		else:
			z = maxi(0, int(round(-tl.position.y / 16.0)))

		# 将画了任意瓦片（占位图）的格子提取到 GridData.turf_grid 中
		for cell in tl.get_used_cells():
			GridData.set_turf(cell, z, true)

		# 提取完毕后清空占位图并隐藏原编辑层（后续由双网格系统统一渲染）
		tl.clear()
		if z > 0:
			tl.visible = false

# 准备第 0 层平坦地面的专用双网格渲染层
func _setup_floor0_turf_layer() -> void:
	if layers_node == null:
		return

	# 检查是否已有现成的 turf1 或 turf_layer1
	var existing = layers_node.get_node_or_null("turf1") as TileMapLayer
	if existing == null:
		existing = layers_node.get_node_or_null("turf_layer1") as TileMapLayer
	if existing:
		floor0_turf_layer = existing
	else:
		floor0_turf_layer = TileMapLayer.new()
		floor0_turf_layer.name = "turf1"
		# 插入到 layer1 后面
		var layer1 = layers_node.get_node_or_null("layer1")
		if layer1:
			var idx := layer1.get_index() + 1
			layers_node.add_child(floor0_turf_layer)
			layers_node.move_child(floor0_turf_layer, idx)
		else:
			layers_node.add_child(floor0_turf_layer)

	floor0_turf_layer.tile_set = grass_tileset
	# 双网格在第 0 层向上偏移半格 (-16px)，使显示格中心对齐 4 个地砖交汇点
	floor0_turf_layer.position = Vector2(0.0, -16.0)
	floor0_turf_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	floor0_turf_layer.y_sort_enabled = true
	floor0_turf_layer.visible = true

# 全量根据当前 GridData.turf_grid 重新计算并刷新双网格贴图
func rebuild_all_turf() -> void:
	if floor0_turf_layer:
		floor0_turf_layer.clear()

	var affected_by_floor: Dictionary = {} # z -> Dictionary of dual_cell -> true
	for k in GridData.turf_grid.keys():
		var cell := Vector2i(k.x, k.y)
		var z: int = k.z
		if not affected_by_floor.has(z):
			affected_by_floor[z] = {}
		for d in _get_affected_dual_cells(cell):
			affected_by_floor[z][d] = true

	for z in affected_by_floor.keys():
		for d in affected_by_floor[z].keys():
			_update_dual_cell(d.x, d.y, z)

# 放置或铲除某格草皮（运行时调用）
func set_turf(cell: Vector2i, z: int, exists: bool) -> void:
	GridData.set_turf(cell, z, exists)
	# 刷新触碰到该格子的 4 个双网格交点
	for d in _get_affected_dual_cells(cell):
		_update_dual_cell(d.x, d.y, z)

# 某格是否有草皮
func has_turf(cell: Vector2i, z: int) -> bool:
	return GridData.has_turf(cell, z)

# 获取逻辑网格 (x, y) 触碰到的 4 个双网格交点坐标 (适配交错等距网格 TILE_LAYOUT_STACKED)
func _get_affected_dual_cells(cell: Vector2i) -> Array[Vector2i]:
	var is_odd := (absi(cell.y) % 2 == 1)
	if is_odd:
		return [
			Vector2i(cell.x, cell.y),         # cell 是该双格的下角 (B)
			Vector2i(cell.x, cell.y + 2),     # cell 是该双格的上角 (T)
			Vector2i(cell.x, cell.y + 1),     # cell 是该双格的右角 (R)
			Vector2i(cell.x + 1, cell.y + 1), # cell 是该双格的左角 (L)
		]
	else:
		return [
			Vector2i(cell.x, cell.y),         # cell 是该双格的下角 (B)
			Vector2i(cell.x, cell.y + 2),     # cell 是该双格的上角 (T)
			Vector2i(cell.x - 1, cell.y + 1), # cell 是该双格的右角 (R)
			Vector2i(cell.x, cell.y + 1),     # cell 是该双格的左角 (L)
		]

# 更新单个双网格交点 (u, v) 在第 z 层的贴图
func _update_dual_cell(u: int, v: int, z: int) -> void:
	var is_odd := (absi(v) % 2 == 1)
	var top_cell := Vector2i(u, v - 2)
	var bottom_cell := Vector2i(u, v)
	var right_cell: Vector2i
	var left_cell: Vector2i
	if is_odd:
		right_cell = Vector2i(u + 1, v - 1)
		left_cell = Vector2i(u, v - 1)
	else:
		right_cell = Vector2i(u, v - 1)
		left_cell = Vector2i(u - 1, v - 1)

	# 计算该交点四周 4 个逻辑角的草皮存在情况 (4-bit 掩码)
	var mask := 0
	if GridData.has_turf(top_cell, z):    mask |= 1 # Top (上)
	if GridData.has_turf(right_cell, z):  mask |= 2 # Right (右)
	if GridData.has_turf(left_cell, z):   mask |= 4 # Left (左)
	if GridData.has_turf(bottom_cell, z): mask |= 8 # Bottom (下)

	if z == 0:
		# 0 层平坦地面：直接画在底板 floor0_turf_layer 上
		if floor0_turf_layer:
			if mask == 0:
				floor0_turf_layer.erase_cell(Vector2i(u, v))
			else:
				floor0_turf_layer.set_cell(Vector2i(u, v), 0, MASK_TO_ATLAS[mask])
	else:
		# 1 层及以上立体高台：进入 sort_world 参与同格精细深度排序
		if sort_world == null:
			return
		var key := "turf_z%d_%d_%d" % [z, u, v]
		var d_layer := sort_world.get_node_or_null(key) as TileMapLayer
		if mask == 0:
			if d_layer:
				d_layer.queue_free()
		else:
			if d_layer == null:
				d_layer = cell_script.new()
				d_layer.name = key
				d_layer.tile_set = grass_tileset
				d_layer.position = Vector2(0.0, -float(z) * 16.0 - 16.0)
				d_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				d_layer.y_sort_enabled = true
				d_layer.collision_enabled = false
				# 排序深度：与该格泥土对齐，但次键比泥土(z)高 0.1，确保盖在泥土顶面，且在麦子/实体(999)底下
				d_layer.set("sort_key", GridData.cell_to_sort_key(Vector2i(u, v)))
				d_layer.set("layer_no", float(z) + 0.1)
				sort_world.add_child(d_layer)
				if sort_world.has_method("insert_sort"):
					sort_world.call("insert_sort", d_layer)
			d_layer.set_cell(Vector2i(u, v), 0, MASK_TO_ATLAS[mask])
