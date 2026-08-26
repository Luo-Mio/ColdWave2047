# main_scene.gd —— 场景组装
extends Node2D

func _ready() -> void:
	# 1. 从 layers 容器收集所有层,按楼层从低到高排序
	var tile_layers: Array[TileMapLayer] = []
	for child in $layers.get_children():
		if child is TileMapLayer:
			tile_layers.append(child)
	tile_layers.sort_custom(func(a: TileMapLayer, b: TileMapLayer) -> bool:
		return a.position.y > b.position.y
	)

	# 2. 建高度场(必须先于拆行!)
	GridData.build_from_layers(tile_layers)

	# 3. 拆行:把每层拆成行级层,填进 sortWorld
	_split_layers_into_rows(tile_layers, $sortworld)

	# 4. 原层隐藏(行级层已替代它绘制)
	for layer in tile_layers:
		layer.visible = false

	# 5. 初始排序一次
	$sortworld.sort_now()

	print("===== 排序诊断 =====")
	for child in $sortworld.get_children():
		print(child.name, "  sort_key=", child.sort_key, "  layer_no=", child.layer_no)


# 把每一层拆成"行级 TileMapLayer"
# 等距行 = cell.x + cell.y(屏幕 y 相同的一串格子)
func _split_layers_into_rows(tile_layers: Array[TileMapLayer], sort_world: Node2D) -> void:
	var row_script: GDScript = load("res://script/row_layer.gd") as GDScript

	for z in tile_layers.size():
		var layer: TileMapLayer = tile_layers[z]

		# 1) 按行分组:row -> Array[cell]
		var by_row: Dictionary = {}
		for cell in layer.get_used_cells():
			var row := cell.x + cell.y
			if not by_row.has(row):
				by_row[row] = []
			by_row[row].append(cell)

		# 2) 每行创建一个行级层
		for row in by_row:
			var row_layer: TileMapLayer = row_script.new()
			row_layer.name = "row_z%d_r%d" % [z, row]
			row_layer.tile_set = layer.tile_set
			row_layer.position = layer.position      # 保留楼层偏移(绘制位置)
			row_layer.y_sort_enabled = true          # 排序交给 sortWorld 手动接管
			row_layer.collision_enabled = false       # 第一阶段先禁用碰撞

			# 拷贝这一行的砖(含 atlas 坐标)
			for cell in by_row[row]:
				row_layer.set_cell(
					cell,
					layer.get_cell_source_id(cell),
					layer.get_cell_atlas_coords(cell),
					layer.get_cell_alternative_tile(cell)
				)

			# 行级层排序键 = 该行所有砖里"键最小"(最靠东)的那个
			# 这样比行内所有砖更靠东的角色,键更小 → 先画 → 被砖盖
			var row_key := INF
			for cell_check in by_row[row]:
				var k := GridData.cell_to_sort_key(cell_check)
				if k < row_key:
					row_key = k
			row_layer.sort_key = row_key


			sort_world.add_child(row_layer)
