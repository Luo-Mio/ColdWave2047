# animation_controller.gd —— 角色动画控制器（朝向严格锁定鼠标，支持平移倒退走）
class_name AnimationController
extends Node

var current_anim: String = "walkSouth"

# 根据【鼠标瞄准方向】决定朝向，根据【WASD移动输入】决定播放/待机
func update_animation(input_dir: Vector2, aim_dir: Vector2, sprite: AnimatedSprite2D) -> void:
	if sprite == null:
		return

	# 1. 朝向永远由鼠标所在方位决定！
	var facing_anim := _get_facing_anim(aim_dir)
	current_anim = facing_anim

	# 2. 如果玩家有 WASD 移动输入，播放行走动画（支持倒退走）；如果没有，定格在第一帧
	if input_dir != Vector2.ZERO:
		if sprite.animation != current_anim or not sprite.is_playing():
			sprite.play(current_anim)
	else:
		sprite.stop()
		sprite.animation = current_anim
		sprite.frame = 0

# 根据鼠标向量映射到 4 轴朝向：East, West, North, South
func _get_facing_anim(dir: Vector2) -> String:
	if absf(dir.x) > absf(dir.y):
		return "walkEast" if dir.x > 0.0 else "walkWest"
	else:
		return "walkSouth" if dir.y > 0.0 else "walkNorth"