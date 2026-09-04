# player_input_component.gd —— 玩家输入大脑组件 (解耦键盘按键与生物肉体)
class_name PlayerInputComponent
extends Node

@export_group("输入控制开关")
## 是否激活玩家按键输入控制。设为 false 时将屏蔽键盘移动（可用于剧情对话、被眩晕冰冻或骑乘接管）
@export var is_active: bool = true
## 角色是否始终面朝鼠标指针方向。开启后主角将随鼠标瞄准实时转向，并支持平移倒退走
@export var always_face_mouse: bool = true

# 获取期望的移动方向向量 (归一化)
func get_movement_direction(_delta: float = 0.0) -> Vector2:
	if not is_active:
		return Vector2.ZERO

	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1.0
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1.0
	if Input.is_action_pressed("move_down"):
		input_dir.y += 1.0
	if Input.is_action_pressed("move_up"):
		input_dir.y -= 1.0

	return input_dir.normalized()

# 获取鼠标相对于指定原点的世界朝向向量
func get_aim_direction(origin_world_pos: Vector2) -> Vector2:
	var parent_2d := _get_parent_2d()
	if parent_2d:
		return (parent_2d.get_global_mouse_position() - origin_world_pos).normalized()
	return Vector2.ZERO

func _get_parent_2d() -> Node2D:
	var curr := get_parent()
	while curr:
		if curr is Node2D:
			return curr as Node2D
		curr = curr.get_parent()
	return null

