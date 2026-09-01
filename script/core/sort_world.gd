# sort_world.gd —— 手动排序容器
extends Node2D

# 比较两个渲染项的顺序(a 是否应排在 b 前)
func _less_than(a: Node, b: Node) -> bool:
	if a.sort_key != b.sort_key:
		return a.sort_key < b.sort_key
	# 相同深度时：地砖先画，实体后画盖砖
	var a_is_entity := ("foot_y" in a) and not (a is TileMapLayer)
	var b_is_entity := ("foot_y" in b) and not (b is TileMapLayer)
	if a_is_entity and not b_is_entity:
		return false
	if not a_is_entity and b_is_entity:
		return true
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
