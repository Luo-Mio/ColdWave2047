# mover_component.gd —— 生物/角色物理运动与平滑驱动通用组件
class_name MoverComponent
extends Node

@export_group("物理移动与平滑参数")
## 基础最大移动速度 (像素/秒)。主角建议 80~120，狼/野兽建议 100~160
@export var move_speed: float = 100.0
## 起步加速度 (像素/秒²)。数值越大起步越灵敏，数值越小越有惯性厚重感
@export var acceleration: float = 1200.0
## 停止时的地面摩擦阻尼 (像素/秒²)。数值越大松手刹车越干脆，数值越小滑行越明显
@export var friction: float = 1000.0
## 是否吸附 2:1 等距斜向 (斜率 ±0.5)。开启后 WASD 八向输入将贴合等距菱形网格行走路线，手感更规范
@export var snap_iso_diagonal: bool = false

var parent_body: CharacterBody2D

func _ready() -> void:
	var curr := get_parent()
	while curr:
		if curr is CharacterBody2D:
			parent_body = curr as CharacterBody2D
			break
		curr = curr.get_parent()

# 接收目标方向向量，平滑加速并驱动物理滑动
func move(target_dir: Vector2, delta: float) -> Vector2:
	if parent_body == null:
		return Vector2.ZERO

	var move_dir := target_dir
	# 2:1 等距对角斜率吸附
	if snap_iso_diagonal and target_dir.x != 0.0 and target_dir.y != 0.0:
		move_dir = Vector2(
			signf(target_dir.x) * 16.0,
			signf(target_dir.y) * 8.0
		).normalized()

	var target_velocity := move_dir * move_speed

	if move_dir != Vector2.ZERO:
		parent_body.velocity = parent_body.velocity.move_toward(target_velocity, acceleration * delta)
	else:
		parent_body.velocity = parent_body.velocity.move_toward(Vector2.ZERO, friction * delta)

	parent_body.move_and_slide()
	return parent_body.velocity

# 立即刹车停下
func stop(delta: float) -> void:
	if parent_body == null:
		return
	parent_body.velocity = parent_body.velocity.move_toward(Vector2.ZERO, friction * delta)
	parent_body.move_and_slide()

