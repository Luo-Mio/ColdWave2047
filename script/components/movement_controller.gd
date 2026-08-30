# movement_controller.gd —— 角色移动控制组件
class_name MovementController
extends Node

@export var move_speed: float = 60.0

# 计算当前帧的移动速度向量
func get_movement_velocity() -> Vector2:
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1.0
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1.0
	if Input.is_action_pressed("move_down"):
		input_dir.y += 1.0
	if Input.is_action_pressed("move_up"):
		input_dir.y -= 1.0
	input_dir = input_dir.normalized()

	var move_dir := input_dir
	# 对角移动: 吸附到最近的 2:1 等距格子边方向(斜率 ±0.5)
	if input_dir.x != 0.0 and input_dir.y != 0.0:
		move_dir = Vector2(
			signf(input_dir.x) * 16.0,
			signf(input_dir.y) * 8.0
		).normalized()

	return move_dir * move_speed

# 获取输入原始方向向量（用于驱动动画）
func get_input_direction() -> Vector2:
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

