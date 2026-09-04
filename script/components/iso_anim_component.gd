# iso_anim_component.gd —— 2.5D 等距生物动画朝向解析与播放通用组件
class_name IsoAnimComponent
extends Node

enum AnimMode {
	CARDINAL_4 = 0, # 正四向：East, West, North, South (适合主角)
	DIAGONAL_4 = 1, # 斜四向：EastSouth, EastNorth, WestSouth, WestNorth (带状态记忆，适合狼/怪物)
}

@export_group("动画朝向与前缀配置")
@export var anim_mode: AnimMode = AnimMode.DIAGONAL_4
# 待机动画前缀 (如主角为 "walk" 停止或 "idle"，狼为 "idel")
@export var idle_prefix: String = "idle"
# 移动动画前缀 (如主角为 "walk"，狼为 "run")
@export var move_prefix: String = "walk"

var sprite: AnimatedSprite2D
# 方向状态记忆 (用于横向/竖向移动时自然映射到上一次偏好的斜向动画)
var _facing_dir: Vector2 = Vector2(1.0, 1.0)
var current_anim: String = ""

func _ready() -> void:
	var curr := get_parent()
	while curr:
		if curr is Node2D:
			sprite = curr.find_child("AnimatedSprite2D", true, false) as AnimatedSprite2D
			if sprite:
				break
		curr = curr.get_parent()

# 核心驱动函数：move_vec 为移动速度/输入，look_vec 为额外凝视/瞄准方向 (可选)
func update_animation(move_vec: Vector2, look_vec: Vector2 = Vector2.ZERO) -> void:
	if sprite == null:
		return

	var is_moving := (move_vec.length_squared() > 1.0)
	var dir := look_vec if (look_vec != Vector2.ZERO) else move_vec

	# 1. 更新朝向状态记忆
	if dir.x != 0.0:
		_facing_dir.x = signf(dir.x)
	if dir.y != 0.0:
		_facing_dir.y = signf(dir.y)

	var dir_suffix := ""
	if anim_mode == AnimMode.DIAGONAL_4:
		# 4 斜向解析
		if _facing_dir.x >= 0.0:
			dir_suffix = "EastSouth" if _facing_dir.y >= 0.0 else "EastNorth"
		else:
			dir_suffix = "WestSouth" if _facing_dir.y >= 0.0 else "WestNorth"
	else:
		# 正 4 轴解析
		if absf(dir.x) > absf(dir.y):
			dir_suffix = "East" if dir.x > 0.0 else "West"
		else:
			dir_suffix = "South" if dir.y > 0.0 else "North"

	# 2. 组装动画名
	var prefix := move_prefix if is_moving else idle_prefix
	var target_anim := prefix + dir_suffix

	# 3. 播放并切换
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(target_anim):
		if sprite.animation != target_anim or (is_moving and not sprite.is_playing()):
			sprite.play(target_anim)
		elif not is_moving and anim_mode == AnimMode.CARDINAL_4:
			# 正4向若无单独待机动画，定格在当前朝向第0帧
			sprite.stop()
			sprite.frame = 0
	current_anim = target_anim

