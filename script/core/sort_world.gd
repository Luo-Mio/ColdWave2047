# sort_world.gd —— 手动排序容器
extends Node2D


# 比较两个渲染项的顺序(a 是否应排在 b 前)
func _less_than(a: Node, b: Node) -> bool:
	if a.sort_key != b.sort_key:
		return a.sort_key < b.sort_key
	# 同格:
	var a_is_entity := "foot_y" in a
	var b_is_entity := "foot_y" in b
	if a_is_entity and b_is_entity:
		return a.foot_y < b.foot_y          # 角色/物体:比精确脚底 y
	if a_is_entity:
		return false                          # 实体不排在砖前 → 实体后画(盖砖)
	if b_is_entity:
		return true
	return a.layer_no < b.layer_no           # 砖 vs 砖:比层号(叠砖)


# 把单个动态节点插入到正确位置(静态砖已有序,二分查找 O(log N))
func insert_sort(node: Node) -> void:
	if not ("sort_key" in node and "layer_no" in node):
		return
	var lo := 0
	var hi := get_child_count()
	while lo < hi:
		var mid := (lo + hi) / 2
		if _less_than(node, get_child(mid)):
			hi = mid
		else:
			lo = mid + 1
	if lo != node.get_index():                # 位置没变就不动,避免闪烁
		move_child(node, lo)


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
