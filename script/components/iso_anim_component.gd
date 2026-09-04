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
# 正四向方向记忆 (East, West, South, North)，停止移动时不会丢失朝向
var _cardinal_dir: String = "South"
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

	# 1. 当有移动/凝视输入时，更新朝向状态记忆
	if dir != Vector2.ZERO:
		if dir.x != 0.0:
			_facing_dir.x = signf(dir.x)
		if dir.y != 0.0:
			_facing_dir.y = signf(dir.y)

		# 更新正 4 轴记忆
		if absf(dir.x) > absf(dir.y):
			_cardinal_dir = "East" if dir.x > 0.0 else "West"
		elif dir.y != 0.0:
			_cardinal_dir = "South" if dir.y > 0.0 else "North"

	var dir_suffix := ""
	if anim_mode == AnimMode.DIAGONAL_4:
		# 4 斜向解析
		if _facing_dir.x >= 0.0:
			dir_suffix = "EastSouth" if _facing_dir.y >= 0.0 else "EastNorth"
		else:
			dir_suffix = "WestSouth" if _facing_dir.y >= 0.0 else "WestNorth"
	else:
		# 正 4 轴解析：直接读取记忆中的朝向，停止移动时绝不重置为 North
		dir_suffix = _cardinal_dir

	# 2. 组装目标动画名
	var target_anim := ""
	if is_moving:
		target_anim = move_prefix + dir_suffix
	else:
		target_anim = idle_prefix + dir_suffix
		# 若没有独立的待机动画，回退到移动动画名
		if not (sprite.sprite_frames and sprite.sprite_frames.has_animation(target_anim)):
			target_anim = move_prefix + dir_suffix

	# 3. 播放并切换
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(target_anim):
		if is_moving:
			if sprite.animation != target_anim or not sprite.is_playing():
				sprite.play(target_anim)
		else:
			# 停止移动时
			if idle_prefix == move_prefix or target_anim == (move_prefix + dir_suffix):
				# 待机复用移动动画（如主角 walkEast/walkSouth）：停止播放并精确回到第 0 帧
				if sprite.animation != target_anim:
					sprite.animation = target_anim
				sprite.stop()
				sprite.frame = 0
			else:
				# 独立待机动画（如狼的 idelEastSouth）：正常播放待机循环
				if sprite.animation != target_anim or not sprite.is_playing():
					sprite.play(target_anim)

	current_anim = target_anim

# 获取动画组件当前的身体朝向向量
func get_facing_direction() -> Vector2:
	if anim_mode == AnimMode.CARDINAL_4:
		match _cardinal_dir:
			"East": return Vector2.RIGHT
			"West": return Vector2.LEFT
			"South": return Vector2.DOWN
			"North": return Vector2.UP
	return _facing_dir.normalized()

