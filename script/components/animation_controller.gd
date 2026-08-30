# animation_controller.gd —— 角色动画控制组件（精准适配 4 轴行走动画与待机定格）
class_name AnimationController
extends Node

var current_anim: String = "walkSouth"

# 根据输入方向更新动画
func update_animation(input_dir: Vector2, sprite: AnimatedSprite2D) -> void:
	if sprite == null:
		return

	if input_dir != Vector2.ZERO:
		var anim := _get_walk_anim(input_dir)
		if anim != current_anim or not sprite.is_playing():
			current_anim = anim
			sprite.play(current_anim)
	else:
		# 待机时定格在当前朝向的第一帧
		sprite.stop()
		sprite.frame = 0

# 根据输入向量映射到现有 4 轴动画：walkEast, walkWest, walkNorth, walkSouth
func _get_walk_anim(dir: Vector2) -> String:
	if absf(dir.x) > absf(dir.y):
		return "walkEast" if dir.x > 0.0 else "walkWest"
	else:
		return "walkSouth" if dir.y > 0.0 else "walkNorth"
