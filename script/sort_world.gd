# sort_world.gd —— 手动排序容器
extends Node2D

# 重新排序所有子节点。
# 消除闪烁的两个关键:
#   ① 比较器末尾用实例 ID 兜底 → 排序结果永远稳定(不会随机换序);
#   ② 顺序没变就不 move_child → 避免每帧把行级层摘下来重插。
func sort_now() -> void:
	var items := get_children()
	items.sort_custom(func(a: Node, b: Node) -> bool:
		if a.sort_key != b.sort_key:
			return a.sort_key < b.sort_key
		if a.layer_no != b.layer_no:
			return a.layer_no < b.layer_no
		return a.get_instance_id() < b.get_instance_id()
	)

	# 先检查顺序是否真的变了
	var need_move := false
	for i in items.size():
		if items[i].get_index() != i:
			need_move = true
			break
	if not need_move:
		return

	# 确实变了才重排
	for i in items.size():
		move_child(items[i], i)
