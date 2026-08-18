# main_scene.gd —— 挂在你主场景的根节点 mainScene 上
extends Node2D

func _ready() -> void:
	# 自动收集场景里所有 TileMapLayer 子节点（不用手动挨个写）
	# 不管你有 3 层还是 64 层，只要它们是 mainScene 的直接子节点都能收集到
	var tile_layers: Array[TileMapLayer] = []
	for child in get_children():
		if child is TileMapLayer:
			tile_layers.append(child)

	# 按 position.y 从大到小排序（见下方说明）
	tile_layers.sort_custom(func(a: TileMapLayer, b: TileMapLayer) -> bool:
		return a.position.y > b.position.y
	)

	# 传给高度场构建（注意：Autoload 节点名是 GridDate，不是 GridData）
	GridData.build_from_layers(tile_layers)
	print("高度场已构建，共 ", GridData.grid.size(), " 条数据")
