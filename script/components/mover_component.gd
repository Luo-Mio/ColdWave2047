# mover_component.gd —— 通用物理移动驱动组件 (支持 2:1 等距视角透视投影)
class_name MoverComponent
extends Node

@export_group("移动参数")
## 基础最大横向移动速度 (像素/秒)
@export var move_speed: float = 120.0
## 起步加速度 (像素/秒²)，数值越大起步越灵敏
@export var acceleration: float = 1200.0
## 刹车阻尼摩擦力 (像素/秒²)，数值越大松手停得越快
@export var friction: float = 1200.0

@export_group("2:1 等距视角透视修正")
## 是否开启 2:1 等距视角速度与斜向吸附 (开启后: 竖向速度为横向 1/2，斜向速度约为横向 79.1%，斜向严格贴合 2:1 菱形边)
@export var snap_iso_diagonal: bool = true

var parent_body: CharacterBody2D

func _ready() -> void:
	# 向上寻找所属的 CharacterBody2D 实体
	var curr := get_parent()
	while curr:
		if curr is CharacterBody2D:
			parent_body = curr as CharacterBody2D
			break
		curr = curr.get_parent()

## 核心物理驱动：传入目标方向向量并执行移动
func move(input_dir: Vector2, delta: float) -> Vector2:
	if parent_body == null:
		return Vector2.ZERO

	var target_velocity := Vector2.ZERO

	if input_dir != Vector2.ZERO:
		if snap_iso_diagonal:
			# 2:1 等距透视投影速度模型：
			# - 纯横向 (A/D): 速度为 1.0 * move_speed (100%)
			# - 纯竖向 (W/S): 速度为 0.5 * move_speed (50%，严格为横向 1/2)
			# - 斜向 (W+D等): 速度约为 0.791 * move_speed (sqrt(10)/4)，斜率严格为 ±0.5 (2:1 菱形地砖切线)
			target_velocity = Vector2(input_dir.x, input_dir.y * 0.5) * move_speed
		else:
			target_velocity = input_dir * move_speed

	# 平滑加速与减速阻尼
	if target_velocity != Vector2.ZERO:
		parent_body.velocity = parent_body.velocity.move_toward(target_velocity, acceleration * delta)
	else:
		parent_body.velocity = parent_body.velocity.move_toward(Vector2.ZERO, friction * delta)

	parent_body.move_and_slide()
	return parent_body.velocity

## 强制立即刹车
func stop(delta: float) -> void:
	if parent_body:
		parent_body.velocity = parent_body.velocity.move_toward(Vector2.ZERO, friction * delta)
		parent_body.move_and_slide()
