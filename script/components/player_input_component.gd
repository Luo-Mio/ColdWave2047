# player_input_component.gd —— 玩家输入大脑组件 (解耦键盘按键与角色实体)
class_name PlayerInputComponent
extends Node

@export_group("输入设置")
## 是否激活输入。对话或暂停时可设为 false 禁用移动
@export var is_active: bool = true

## 获取经过归一化的 8 向输入向量
func get_movement_direction() -> Vector2:
	if not is_active:
		return Vector2.ZERO

	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_right"):
		dir.x += 1.0
	if Input.is_action_pressed("move_left"):
		dir.x -= 1.0
	if Input.is_action_pressed("move_down"):
		dir.y += 1.0
	if Input.is_action_pressed("move_up"):
		dir.y -= 1.0

	# 归一化，防止对角线直接叠加导致根号2超速
	return dir.normalized()

