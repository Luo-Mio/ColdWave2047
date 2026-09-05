# selector.gd —— 极致性能几何种植网格与直觉鼠标微格拾取器
extends Node2D

@export var player_path: NodePath          # 指向玩家节点
@export var interaction_range: int = 2     # 几何范围半径 (1 = 对称 3x3 菱形 9格, 2 = 对称 5x5 菱形 25格)

var target_cell: Vector2i = Vector2i(-99999, -99999)      # 当前选中的大格
var target_sub_cell: Vector2i = Vector2i(0, 0)            # 当前选中的微格 (0~3, 0~3)

# 缓存与脏标记
var _last_target_cell: Vector2i = Vector2i(-99999, -99999)
var _last_target_sub_cell: Vector2i = Vector2i(-1, -1)
var _last_player_cell: Vector2i = Vector2i(-99999, -99999)
var _last_item_key: String = ""
var _cached_tiles: Array[Dictionary] = [] # 缓存当前周围有效格子的空间数据

@onready var hotbar_node: Node = get_node_or_null("../hotbar")

func _ready() -> void:
	z_index = 100
	if hotbar_node == null:
		hotbar_node = get_tree().root.find_child("hotbar", true, false)

func _process(_delta: float) -> void:
	_update_mouse_selection()

func force_update() -> void:
	_last_target_cell = Vector2i(-99999, -99999)
	_last_player_cell = Vector2i(-99999, -99999)
	_last_item_key = ""
	_update_mouse_selection()
	queue_redraw()

# 仅当角色换格子时，更新一次周围有效格子的空间数据缓存（去重优化）
func _rebuild_tile_cache(player: Node2D) -> void:
	_cached_tiles.clear()
	var player_cell := GridData.world_to_cell(player.global_position)
	var player_floor := GridData.get_highest_floor(player_cell)
	var player_ground_pos := GridData.cell_to_world(player_cell) + Vector2(0.0, GridData.get_floor_pixel_offset(player_floor))
	# 2:1 等距网格中，Y 轴每行仅为 8px，因此 Y 方向需要双倍扫描行数
	var scan_rx := interaction_range + 1
	var scan_ry := interaction_range * 2 + 1
	for dy in range(-scan_ry, scan_ry + 1):
		for dx in range(-scan_rx, scan_rx + 1):
			var cell := player_cell + Vector2i(dx, dy)
			if not GridData.has_any_tile(cell):
				continue

			var floor_val := GridData.get_highest_floor(cell)
			if floor_val != player_floor:
				continue

			var cell_top := GridData.cell_to_world(cell) + Vector2(0.0, GridData.get_floor_pixel_offset(floor_val))
			var delta := cell_top - player_ground_pos
			var iso_dist: float = (absf(delta.x) / 64.0) + (absf(delta.y) / 32.0) 
			if iso_dist > float(interaction_range) + 0.15:
				continue

			_cached_tiles.append({
				"cell": cell,
				"top": cell_top,
				"floor": floor_val
			})

# 【直觉鼠标拾取】：直接在缓存中做命中检测
func _update_mouse_selection() -> void:
	if GridData.layers.is_empty():
		return
	var player: Node2D = get_node_or_null(player_path)
	if player == null:
		return

	var player_cell := GridData.world_to_cell(player.global_position)
	var player_moved := (player_cell != _last_player_cell)
	
	# 角色换格子时，更新空间缓存
	if player_moved:
		_last_player_cell = player_cell
		_rebuild_tile_cache(player)

	# 检查手持物品是否发生改变
	var active_item: Dictionary = {}
	if hotbar_node and hotbar_node.has_method("get_active_item"):
		active_item = hotbar_node.call("get_active_item")
	var current_item_key: String = str(active_item.get("type", -1)) + "_" + str(active_item.get("name", ""))
	var item_changed := (current_item_key != _last_item_key)
	if item_changed:
		_last_item_key = current_item_key

	var mouse_pos := get_global_mouse_position()
	var found_cell := Vector2i(-99999, -99999)
	var found_sub := Vector2i(0, 0)

	for tile_data in _cached_tiles:
		var rel: Vector2 = mouse_pos - tile_data["top"]
		if (absf(rel.x) / 32.0) + (absf(rel.y) / 16.0) <= 1.0:
			found_cell = tile_data["cell"]
			found_sub = GridData.world_to_sub_cell(mouse_pos, found_cell)
			break

	target_cell = found_cell
	target_sub_cell = found_sub

	# 只要选区改变、角色移动或切换了物品，立刻重绘！
	if target_cell != _last_target_cell or target_sub_cell != _last_target_sub_cell or player_moved or item_changed:
		_last_target_cell = target_cell
		_last_target_sub_cell = target_sub_cell
		queue_redraw()

# 【合批绘制】：直接遍历缓存数据提交 GPU
func _draw() -> void:
	var player: Node2D = get_node_or_null(player_path)
	if player == null:
		return

	var active_item: Dictionary = {}
	if hotbar_node and hotbar_node.has_method("get_active_item"):
		active_item = hotbar_node.call("get_active_item")

	# 【核心规则】：只有当前手持可放置道具（0=TILE 瓷砖, 1=OBJECT 作物/树木）时才绘制网格！
	var item_type: int = active_item.get("type", -1)
	if item_type != 0 and item_type != 1:
		return

	var is_micro_crop: bool = (active_item.get("grid_size", Vector2i(4, 4)) == Vector2i(1, 1))

	var grid_lines := PackedVector2Array()
	var green_dots := PackedVector2Array()
	var red_dots := PackedVector2Array()

	# 直接复用缓存中的格子数据，不再做任何重复计算
	for tile_data in _cached_tiles:
		var cell: Vector2i = tile_data["cell"]
		var cell_top: Vector2 = tile_data["top"]

		# 绘制 64x32 外边框
		var p_top := cell_top + Vector2(0, -16)    # 原本是 -8
		var p_right := cell_top + Vector2(32, 0)   # 原本是 16
		var p_bot := cell_top + Vector2(0, 16)     # 原本是 8
		var p_left := cell_top + Vector2(-32, 0)   # 原本是 -16
		grid_lines.push_back(p_top); grid_lines.push_back(p_right)
		grid_lines.push_back(p_right); grid_lines.push_back(p_bot)
		grid_lines.push_back(p_bot); grid_lines.push_back(p_left)
		grid_lines.push_back(p_left); grid_lines.push_back(p_top)

		# 16 个微槽位点阵
		var occupancies := GridData.get_cell_sub_occupancies(cell)
		for sy in 4:
			for sx in 4:
				var sp := Vector2i(sx, sy)
				if cell == target_cell and sp == target_sub_cell and is_micro_crop:
					continue
				var sub_center := cell_top + GridData.sub_cell_to_local_offset(sp, Vector2i(1, 1))
				if occupancies[sy * 4 + sx]:
					red_dots.push_back(sub_center + Vector2(-1, 0))
					red_dots.push_back(sub_center + Vector2(1, 0))
				else:
					green_dots.push_back(sub_center + Vector2(-1, 0))
					green_dots.push_back(sub_center + Vector2(1, 0))

	if not grid_lines.is_empty():
		draw_multiline(grid_lines, Color(1.0, 1.0, 1.0, 0.15), 1.0)
	if not green_dots.is_empty():
		draw_multiline(green_dots, Color(0.2, 1.0, 0.4, 0.45), 1.0)
	if not red_dots.is_empty():
		draw_multiline(red_dots, Color(1.0, 0.25, 0.25, 0.65), 1.0)

	# 绘制当前目标高亮
	if target_cell != Vector2i(-99999, -99999):
		var target_floor := GridData.get_highest_floor(target_cell)
		var t_center := GridData.cell_to_world(target_cell) + Vector2(0.0, GridData.get_floor_pixel_offset(target_floor))

		if is_micro_crop:
			# 1. 1x1 微格高亮菱形 (16x8)
			var sub_c := t_center + GridData.sub_cell_to_local_offset(target_sub_cell, Vector2i(1, 1))
			var is_occ := GridData.is_slot_occupied(target_cell, target_sub_cell, Vector2i(1, 1))
			var h_color := Color(1.0, 0.2, 0.2, 0.5) if is_occ else Color(0.2, 1.0, 0.4, 0.6)

			var highlight_pts := PackedVector2Array([
				sub_c + Vector2(0, -4), sub_c + Vector2(8, 0),
				sub_c + Vector2(0, 4), sub_c + Vector2(-8, 0)
			])
			draw_polygon(highlight_pts, PackedColorArray([h_color]))

			var border_pts := PackedVector2Array([
				sub_c + Vector2(0, -4), sub_c + Vector2(8, 0),
				sub_c + Vector2(0, 4), sub_c + Vector2(-8, 0),
				sub_c + Vector2(0, -4)
			])
			draw_polyline(border_pts, Color(1.0, 1.0, 1.0, 0.9), 1.0)
		else:
			# 2. 4x4 整格 / 瓷砖高亮菱形 (64x32)（补回这一段！）
			var is_full_occ := GridData.is_slot_occupied(target_cell, Vector2i.ZERO, Vector2i(4, 4))
			var t_color := Color(1.0, 0.2, 0.2, 0.4) if is_full_occ else Color(1.0, 1.0, 0.0, 0.4)
			var big_diamond := PackedVector2Array([
				t_center + Vector2(0, -16), t_center + Vector2(32, 0),
				t_center + Vector2(0, 16), t_center + Vector2(-32, 0)
			])
			draw_polygon(big_diamond, PackedColorArray([t_color]))

			var big_border := PackedVector2Array([
				t_center + Vector2(0, -16), t_center + Vector2(32, 0),
				t_center + Vector2(0, 16), t_center + Vector2(-32, 0),
				t_center + Vector2(0, -16)
			])
			draw_polyline(big_border, Color(1.0, 1.0, 1.0, 0.9), 1.0)
