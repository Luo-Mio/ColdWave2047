@tool
class_name GameCamera
extends Camera2D

@export_group("目标跟随")
## 跟随的目标节点 (若未指定，运行时自动寻找同场景下的 Main_Chara)
@export var target: Node2D = null

@export_group("镜头设置")
## 镜头距离 / 缩放倍率 (默认 1.0；数值越小拉得越远/俯瞰范围越广，数值越大镜头越近)
@export_range(0.1, 5.0, 0.05) var camera_distance: float = 1.0:
	set(v):
		camera_distance = v
		zoom = Vector2(camera_distance, camera_distance)

func _ready() -> void:
	zoom = Vector2(camera_distance, camera_distance)
	if Engine.is_editor_hint():
		return
	if target == null:
		target = get_parent().get_node_or_null("Main_Chara") as Node2D
		if target == null and get_tree() and get_tree().current_scene:
			target = get_tree().current_scene.find_child("Main_Chara", true, false) as Node2D

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if target and is_instance_valid(target):
		global_position = target.global_position

