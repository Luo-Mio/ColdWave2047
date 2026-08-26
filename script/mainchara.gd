# mainchara.gd —— 主角脚本(格子高度加成·极简版)
extends CharacterBody2D

@export var move_speed: float = 60

# 瓷砖锚点在视觉底面,角色要站在顶面 → 额外上移 8px
@export var foot_offset: float = -8.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

var current_anim: String = "walkSouth"
var sort_key: float = 0.0        # 排序主键(所在格基底 y)
var layer_no: int = 999          # 排序次键:物体永远后画
var _last_sort_key: float = -INF # 防抖:只有换格才重排


func _ready() -> void:
	# 等一帧:确保 mainScene._ready 已构建高度场
	await get_tree().process_frame
	_update_sort_key()


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

	# ---------- 2. 平面移动(节点位置 = 平面逻辑位置) ----------
	velocity = input_dir * move_speed
	move_and_slide()

	# ---------- 3. 高度加成(瞬时,无过渡) ----------
	# 查角色脚下格子的最高层,精灵直接偏移到该层高度
	var cell := GridData.world_to_cell(global_position)
	print("所在格=", cell, " 行=", cell.x + cell.y)
	var floor := GridData.get_highest_floor(cell)
	animated_sprite.position.y = GridData.get_floor_pixel_offset(floor) + foot_offset

	# ---------- 4. 更新排序键(只有换格子才重排) ----------
	_update_sort_key()

	# ---------- 5. 动画 ----------
	if input_dir != Vector2.ZERO:
		var anim := _get_walk_anim(input_dir)
		if anim != current_anim:
			current_anim = anim
		animated_sprite.play(current_anim)
	else:
		animated_sprite.pause()


# 更新排序键,并通知父级排序容器重排
func _update_sort_key() -> void:
	if GridData.layers.is_empty():
		return
	var cell := GridData.world_to_cell(global_position)
	sort_key = GridData.cell_to_sort_key(cell)
	if sort_key != _last_sort_key:
		_last_sort_key = sort_key
		var parent_sort := get_parent()
		if parent_sort and parent_sort.has_method("sort_now"):
			parent_sort.sort_now()


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
