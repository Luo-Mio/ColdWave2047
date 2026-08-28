# selector.gd —— 识别器:从玩家位置朝鼠标方向发射射线,高亮第一个非玩家脚下的方块
extends Node2D

@export var player_path: NodePath          # 指向玩家节点
@export var ray_step: float = 8.0          # 步进精度(像素)
@export var ray_max_steps: int = 100       # 步数上限(防止死循环)
@export var body_radius_x: float = 24.0    # 玩家椭圆半轴(32 宽)
@export var body_radius_y: float = 12.0     # 玩家椭圆半轴(16 高)
@export var update_interval: float = 1.0 / 30.0   # 每秒最多 30 次

var _update_timer: float = 0.0
var _last_mouse: Vector2 = Vector2.INF
var _frame_count: int = 0
var highlight: Polygon2D                   # 高亮菱形(脚本动态创建)
var target_cell: Vector2i = Vector2i(-99999, -99999)   # 当前高亮的目标格

func _ready() -> void:
	await get_tree().process_frame          # 等 mainScene 构建完高度场

	# 动态创建一个菱形高亮(32x16,半透明黄)
	highlight = Polygon2D.new()
	highlight.polygon = PackedVector2Array([
		Vector2(0, -8), Vector2(16, 0), Vector2(0, 8), Vector2(-16, 0)
	])
	highlight.color = Color(1, 1, 0, 0.4)   # 半透明黄
	highlight.z_index = 100                  # 永远画在最上面
	add_child(highlight)
	highlight.visible = false

func _process(_delta: float) -> void:
	# 1) 鼠标没动够 4px,完全跳过(静止时零开销)
	var mouse_pos := get_global_mouse_position()
	if mouse_pos.distance_to(_last_mouse) < 4.0:
		return
	_last_mouse = mouse_pos

	# 2) 节流:每秒最多更新 update_interval 次
	_update_timer += _delta
	if _update_timer < update_interval:
		return
	_update_timer = 0.0

	_update_ray()

# 强制立即刷新高亮(放置/删除瓷砖后调用,跳过阈值和节流)
func force_update() -> void:
	_last_mouse = get_global_mouse_position()
	_update_ray()

# 射线检测:更新高亮位置和目标格
func _update_ray() -> void:
	if GridData.layers.is_empty():
		return
	var player: Node2D = get_node_or_null(player_path)
	if player == null:
		return

	var player_pos := player.global_position
	var mouse_pos := get_global_mouse_position()
	var dir := mouse_pos - player_pos
	if dir.length() < 0.001:
		highlight.visible = false
		target_cell = Vector2i(-99999, -99999)
		return
	dir = dir.normalized()

	var pos := _ray_start(player_pos, dir)
	var player_cell := GridData.world_to_cell(player_pos)

	for i in ray_max_steps:
		var cell := GridData.world_to_cell(pos)
		if cell != player_cell and GridData.has_any_tile(cell):
			_set_highlight(cell)
			return
		pos += dir * ray_step

	highlight.visible = false
	target_cell = Vector2i(-99999, -99999)

# 计算射线与玩家椭圆边缘的交点,作为步进起点
func _ray_start(player_pos: Vector2, dir: Vector2) -> Vector2:
	var t := 1.0 / sqrt(
		(dir.x / body_radius_x) * (dir.x / body_radius_x) +
		(dir.y / body_radius_y) * (dir.y / body_radius_y)
	)
	# 稍微超出椭圆边缘(1% 余量),避免起点落在椭圆内
	return player_pos + dir * t * 1.01


# _set_highlight 里,记录目标格:
func _set_highlight(cell: Vector2i) -> void:
	target_cell = cell          # ← 加这行
	var floor := GridData.get_highest_floor(cell)
	# print("命中 cell=", cell, " floor=", floor)   # 调试,已注释
	highlight.position = GridData.cell_to_world(cell) + Vector2(
		0.0,
		GridData.get_floor_pixel_offset(floor)
	)
	highlight.visible = true
	
