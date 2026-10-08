# sort_world.gd —— 手动排序容器 (支持多楼层立体地表与实体深度精准消隐)
extends Node2D

# 比较两个渲染项的顺序(a 是否应排在 b 前)
func _less_than(a: Node, b: Node) -> bool:
	var a_is_entity := ("foot_y" in a) and not (a is TileMapLayer)
	var b_is_entity := ("foot_y" in b) and not (b is TileMapLayer)

	# 1. 实体 与 地形/地表切片 之间的多层物理排序法则
	if a_is_entity != b_is_entity:
		var entity_node: Node = a if a_is_entity else b
		var terrain_node: Node = b if a_is_entity else a

		var e_floor: int = 0
		if "floor_level" in entity_node:
			e_floor = int(entity_node.floor_level)
		elif "current_floor" in entity_node:
			e_floor = int(entity_node.current_floor)
		elif "base_position" in entity_node and entity_node.base_position != Vector2.ZERO:
			e_floor = GridData.get_highest_floor(GridData.world_to_cell(entity_node.base_position))
		else:
			e_floor = GridData.get_highest_floor(GridData.world_to_cell(entity_node.global_position))

		var t_layer: float = terrain_node.layer_no if "layer_no" in terrain_node else 0.0
		var t_floor: int = int(floor(t_layer))

		# 核心物理法则：
		# 当地形与实体处于同一楼层或更低楼层 (t_floor <= e_floor) 时，
		# 该地形必然是实体脚下的基底地砖或地表草皮！地表永远在实体脚底之下，绝不允许盖住实体根部！
		if t_layer < 900.0 and t_floor <= e_floor:
			# 地形必须先画 (排在实体之前)，实体后画 (盖在地表草皮之上)
			return not a_is_entity

		# 如果地形处于更高楼层 (t_floor > e_floor)，则该地形属于高台立面/高墙障碍，
		# 遵循经典 2.5D 深度规则：南侧障碍遮挡北侧生物，北侧障碍在生物后方
		if a.sort_key != b.sort_key:
			return a.sort_key < b.sort_key
		return not a_is_entity

	# 2. 两个同类项之间 (实体 vs 实体，或 地形 vs 地形)
	if a.sort_key != b.sort_key:
		return a.sort_key < b.sort_key

	return a.layer_no < b.layer_no

# 把单个动态节点插入到正确位置（极速平稳的相邻位比对，零抖动）
func insert_sort(node: Node) -> void:
	if not ("sort_key" in node and "layer_no" in node):
		return
	var curr_idx := node.get_index()
	var child_cnt := get_child_count()
	
	# 向前寻找插入点
	var target_idx := curr_idx
	while target_idx > 0 and _less_than(node, get_child(target_idx - 1)):
		target_idx -= 1
		
	# 向后寻找插入点
	while target_idx < child_cnt - 1 and _less_than(get_child(target_idx + 1), node):
		target_idx += 1
		
	if target_idx != curr_idx:
		move_child(node, target_idx)


# 重新排序所有子节点
func sort_now() -> void:
	var items := get_children()
	items = items.filter(func(n: Node) -> bool:
		return "sort_key" in n and "layer_no" in n
	)
	items.sort_custom(func(a: Node, b: Node) -> bool:
		return _less_than(a, b)
	)
	for i in items.size():
		if items[i].get_index() != i:
			move_child(items[i], i)
