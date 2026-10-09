# edge_indicate_system.gd —— 2.5D 顶层落差白边视觉指示系统
# 根据 GridData 的边缘拓扑计算结果，在顶层瓷砖上渲染像素级白边高光轮廓
class_name EdgeIndicateSystem
extends Node

static var instance: EdgeIndicateSystem = null

var cell_script: GDScript = preload("res://script/core/row_layer.gd")
var edge_tileset: TileSet = null
var sort_world: Node2D = null
var layers_node: Node2D = null
var edge_layer0: TileMapLayer = null

func _init() -> void:
	instance = self

func _ready() -> void:
	instance = self

# 初始化边缘指示系统
func init_system(sort_world_ref: Node2D, layers_ref: Node2D) -> void:
	instance = self
	sort_world = sort_world_ref
	layers_node = layers_ref

	# 1. 组装专用等距边缘图集 (TipL=1, TipM=2, TipR=3)
	_setup_edge_tileset()

	# 2. 准备第 0 层平坦地表的边缘渲染子层
	_setup_edge_layer0()

	# 3. 监听 GridData 边缘状态变更信号
	if not GridData.edge_changed.is_connected(_on_edge_changed):
		GridData.edge_changed.connect(_on_edge_changed)

	# 4. 全量初始渲染
	rebuild_all_visuals()

# 组装 64x32 等距菱形 TileSet (直接对应 Source ID 1: TipL, 2: TipM, 3: TipR)
func _setup_edge_tileset() -> void:
	edge_tileset = TileSet.new()
	edge_tileset.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	edge_tileset.tile_size = Vector2i(64, 32)

	var tex_l := preload("res://resources/surface/EdgeIndicate/TipL.png")
	var tex_m := preload("res://resources/surface/EdgeIndicate/TipM.png")
	var tex_r := preload("res://resources/surface/EdgeIndicate/TipR.png")

	# Source 1: TipL (左上沿)
	var src_l := TileSetAtlasSource.new()
	src_l.texture = tex_l
	src_l.texture_region_size = Vector2i(64, 64)
	src_l.create_tile(Vector2i(0, 0))
	edge_tileset.add_source(src_l, GridData.EDGE_TIP_L)

	# Source 2: TipM (左右双上沿尖顶)
	var src_m := TileSetAtlasSource.new()
	src_m.texture = tex_m
	src_m.texture_region_size = Vector2i(64, 64)
	src_m.create_tile(Vector2i(0, 0))
	edge_tileset.add_source(src_m, GridData.EDGE_TIP_M)

	# Source 3: TipR (右上沿)
	var src_r := TileSetAtlasSource.new()
	src_r.texture = tex_r
	src_r.texture_region_size = Vector2i(64, 64)
	src_r.create_tile(Vector2i(0, 0))
	edge_tileset.add_source(src_r, GridData.EDGE_TIP_R)

# 准备第 0 层平坦地面边缘渲染层 (挂载在 layers 节点下，紧跟在 floor0_surf_layer 之后)
func _setup_edge_layer0() -> void:
	if layers_node == null:
		return

	edge_layer0 = layers_node.get_node_or_null("EdgeIndicate0") as TileMapLayer
	if edge_layer0 == null:
		edge_layer0 = TileMapLayer.new()
		edge_layer0.name = "EdgeIndicate0"
		layers_node.add_child(edge_layer0)

	edge_layer0.tile_set = edge_tileset
	edge_layer0.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	edge_layer0.position = Vector2.ZERO
	edge_layer0.y_sort_enabled = false
	edge_layer0.z_index = 0
	edge_layer0.material = VisionFogComponent.get_tile_shadow_material()

	# 确保 edge_layer0 位于 layers_node 中所有地砖与地表之后，绝不被泥土或草皮遮挡
	var max_idx := 0
	for child in layers_node.get_children():
		if child != edge_layer0 and child is CanvasItem:
			max_idx = maxi(max_idx, child.get_index())
	layers_node.move_child(edge_layer0, max_idx + 1)

# 全量根据 GridData.edge_grid 刷新所有高亮边缘
func rebuild_all_visuals() -> void:
	if edge_layer0:
		edge_layer0.clear()

	if sort_world:
		var to_remove: Array[Node] = []
		for child in sort_world.get_children():
			if child.name.begins_with("edge_z"):
				to_remove.append(child)
		for node in to_remove:
			node.queue_free()

	for cell in GridData.edge_grid.keys():
		var edge_type: int = GridData.get_edge(cell)
		var z: int = GridData.get_edge_floor(cell)
		if z < 0:
			z = GridData.get_highest_floor(cell)
		update_cell_visual(cell, edge_type, z, -1)

# 响应 GridData 边缘拓扑变更事件
func _on_edge_changed(cell: Vector2i, new_type: int, new_z: int, old_z: int) -> void:
	update_cell_visual(cell, new_type, new_z, old_z)

# 动态更新单个格子的白边视觉呈现
func update_cell_visual(cell: Vector2i, edge_type: int, current_z: int, old_z: int = -1) -> void:
	# 1. 如果旧楼层与新楼层不同，先清理旧楼层上的旧边缘
	if old_z >= 0 and old_z != current_z:
		if old_z == 0:
			if edge_layer0:
				edge_layer0.erase_cell(cell)
		elif sort_world:
			var old_node := sort_world.get_node_or_null("edge_z%d_%d_%d" % [old_z, cell.x, cell.y])
			if old_node:
				old_node.queue_free()

	# 2. 渲染新楼层上的边缘
	if edge_type == GridData.EDGE_NONE or current_z < 0:
		# 无边缘或该格地砖已被完全铲除：彻底清理当前楼层
		if current_z == 0:
			if edge_layer0:
				edge_layer0.erase_cell(cell)
		elif current_z > 0 and sort_world:
			var node := sort_world.get_node_or_null("edge_z%d_%d_%d" % [current_z, cell.x, cell.y])
			if node:
				node.queue_free()
	else:
		# 有边缘
		if current_z == 0:
			# 第 0 层地面
			if edge_layer0:
				edge_layer0.set_cell(cell, edge_type, Vector2i.ZERO, 0)
		else:
			# 1 层及以上立体高台：进入 sort_world 独立参与深度排序 (layer_no = z + 0.2，盖在泥土 z 与草皮 z+0.1 之上)
			if sort_world == null:
				return
			var key := "edge_z%d_%d_%d" % [current_z, cell.x, cell.y]
			var edge_node := sort_world.get_node_or_null(key) as TileMapLayer
			if edge_node == null:
				edge_node = cell_script.new()
				edge_node.name = key
				edge_node.tile_set = edge_tileset
				edge_node.position = Vector2(0.0, -float(current_z) * 16.0)
				edge_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				edge_node.material = VisionFogComponent.get_tile_shadow_material()
				edge_node.collision_enabled = false
				edge_node.set("sort_key", GridData.cell_to_sort_key(cell))
				edge_node.set("layer_no", float(current_z) + 0.2)
				sort_world.add_child(edge_node)
				if sort_world.has_method("insert_sort"):
					sort_world.call("insert_sort", edge_node)
			else:
				edge_node.tile_set = edge_tileset
				edge_node.set("sort_key", GridData.cell_to_sort_key(cell))
				edge_node.set("layer_no", float(current_z) + 0.2)
				if sort_world.has_method("insert_sort"):
					sort_world.call("insert_sort", edge_node)

			edge_node.set_cell(cell, edge_type, Vector2i.ZERO, 0)
