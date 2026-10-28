# four_dir_anim_component.gd —— 通用 4 向动画管理组件 (支持 8 向移动输入映射)
class_name FourDirAnimComponent
extends Node

enum DiagonalBias {
	HORIZONTAL, # 斜向移动偏向播放左右动画 (walk_left / walk_right)
	VERTICAL,   # 斜向移动偏向播放上下动画 (walk_up / walk_down)
	PERSIST     # 斜向移动保持上一次的朝向偏好
}

@export_group("动画配置")
## 动画名称前缀 (你的动画为 walk_up, walk_down, walk_left, walk_right，因此前缀为 "walk_")
@export var anim_prefix: String = "walk_"
## 斜向 8 向走动时，4 向动画的偏向规则
@export var diagonal_bias: DiagonalBias = DiagonalBias.HORIZONTAL
## 停止时的待机帧下标 (通常为第 0 帧)
@export var idle_frame: int = 0

var sprite: AnimatedSprite2D
var last_facing: String = "down"

func _ready() -> void:
	# 向上寻找所属实体的 AnimatedSprite2D
	var curr := get_parent()
	while curr:
		if curr is Node2D:
			sprite = curr.find_child("AnimatedSprite2D", true, false) as AnimatedSprite2D
			if sprite:
				break
		curr = curr.get_parent()

## 根据当前实际移动速度/向量更新动画
func update_animation(velocity: Vector2) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return

	var is_moving := velocity.length_squared() > 1.0

	if is_moving:
		last_facing = _resolve_facing(velocity)
		var target_anim := anim_prefix + last_facing
		if sprite.animation != target_anim or not sprite.is_playing():
			sprite.play(target_anim)
	else:
		# 停止移动：停留在最后朝向的第一帧作为待机
		var target_anim := anim_prefix + last_facing
		if sprite.animation != target_anim:
			sprite.animation = target_anim
		sprite.stop()
		sprite.frame = idle_frame

## 将 8 向移动速度解析为 4 个方向之一 ("up", "down", "left", "right")
func _resolve_facing(dir: Vector2) -> String:
	var abs_x := absf(dir.x)
	var abs_y := absf(dir.y)

	# 纯正交移动检测
	if abs_x > 0.01 and abs_y < 0.01:
		return "right" if dir.x > 0 else "left"
	if abs_y > 0.01 and abs_x < 0.01:
		return "down" if dir.y > 0 else "up"

	# 2:1 等距斜向移动 (abs_x 约为 2 * abs_y)
	match diagonal_bias:
		DiagonalBias.HORIZONTAL:
			return "right" if dir.x > 0 else "left"
		DiagonalBias.VERTICAL:
			return "down" if dir.y > 0 else "up"
		DiagonalBias.PERSIST:
			# 如果之前是上下，就继续用上下；否则用左右
			if last_facing == "up" or last_facing == "down":
				return "down" if dir.y > 0 else "up"
			else:
				return "right" if dir.x > 0 else "left"

	return "down"

