# item_collector.gd —— 自由掉落物磁吸拾取组件
class_name ItemCollector
extends Area2D

signal item_collected(item_id: String, count: int)

@export var pickup_radius: float = 28.0

func _ready() -> void:
	# 碰撞层设置（扫描 Layer 4: 掉落物层）
	collision_layer = 0
	collision_mask = 8
	monitoring = true

	# 自动创建圆形拾取范围碰撞体
	if get_node_or_null("CollisionShape2D") == null:
		var col_shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = pickup_radius
		col_shape.shape = circle
		add_child(col_shape)

	area_entered.connect(_on_area_entered)

func _on_area_entered(area: Area2D) -> void:
	var item := area.get_parent()
	if item and item.has_method("collect_by"):
		var item_info: Dictionary = item.call("collect_by", get_parent())
		if not item_info.is_empty():
			emit_signal("item_collected", item_info.get("id", "dirt"), item_info.get("count", 1))

