# mainchara.gd —— 主角脚本（方式A：直接操控 global_position + 平滑楼层过渡 + 日志）
extends CharacterBody2D


@export var move_speed: float = 60
@export var climb_speed: float = 60.0  # 楼层升降的过渡速度（像素/秒）

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

var current_anim: String = "walkSouth"
var current_floor: int = 0     # 角色逻辑楼层（离散，用于判定）
var visual_offset: float = 0.0 # 当前视觉偏移（连续，平滑过渡中）
var frame_count: int = 0       # 帧计数，用于控制日志频率


func _physics_process(_delta: float) -> void:
	# ---------- 1. 输入 ----------
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

	# ---------- 2. 移动（在"当前已修正"的位置上移动） ----------
	velocity = input_dir * move_speed
	move_and_slide()

	# ---------- 3. 平面坐标 + 查楼层 ----------
	# 平面坐标 = 渲染坐标 - 当前视觉偏移（还原贴地位置用于判定）
	var planar_pos := global_position - Vector2(0.0, visual_offset)
	var cell := GridData.world_to_cell(planar_pos)
	var new_floor := GridData.get_highest_floor(cell)

	# ---------- 4. 楼层变化 → 更新目标偏移（平滑过渡） ----------
	# 楼层变化时，把 current_floor 更新到新楼层，并打印日志；
	# 视觉上不用瞬间跳，交给下面第5步的插值慢慢靠近目标。
	if new_floor != current_floor:
		print("========== 楼层变化 %d -> %d ==========" % [current_floor, new_floor])
		print("  平面坐标      : ", planar_pos)
		print("  视觉偏移      : ", visual_offset)
		current_floor = new_floor

	# ---------- 5. 平滑滑向目标偏移 ----------
	# 目标偏移 = (new_floor+1)*-8；visual_offset 每帧向它靠近，
	# 速度 climb_speed，产生"走上/走下平台"的连贯过渡。
	var target_offset := GridData.get_floor_pixel_offset(current_floor)
	var diff: float = target_offset - visual_offset
	if absf(diff) > 0.1:                              # 还没到位
		var step := climb_speed * _delta
		visual_offset += signf(diff) * minf(step, absf(diff))  # 靠近目标，且不越过
		global_position.y = planar_pos.y + visual_offset        # 渲染位置 = 平面 + 视觉偏移
	else:
		visual_offset = target_offset                  # 到位，吸附精确定位

	# ---------- 6. 周期日志（每 10 帧一次，观察移动/过渡） ----------
	frame_count += 1
	if frame_count % 10 == 0:
		print("平面坐标: %s | 渲染坐标: %s | 楼层: %d | 视觉偏移: %.1f" % [planar_pos, global_position, current_floor, visual_offset])

	# ---------- 7. 动画 ----------
	if input_dir != Vector2.ZERO:
		var anim := _get_walk_anim(input_dir)
		if anim != current_anim:
			current_anim = anim
		animated_sprite.play(current_anim)
	else:
		animated_sprite.pause()


func _get_walk_anim(dir: Vector2) -> String:
	var anim := "walk"
	if dir.x < 0.0:
		anim += "West"
	elif dir.x > 0.0:
		anim += "East"
	elif dir.y < 0.0:
		anim += "North"
	else:
		anim += "South"
	return anim