# selector.gd —— 极致性能几何种植网格与直觉鼠标微格拾取器
extends Node2D

@export var player_path: NodePath          # 指向玩家节点
@export var interaction_range: int = 2     # 几何范围半径 (1 = 对称 3x3 菱形 9格, 2 = 对称 5x5 菱形 25格)
@export var snap_2x2_to_quadrants: bool = true # 2x2 物体是否对齐到 4 个象限 (0,0), (2,0), (0,2), (2,2)

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

	var item_type: int = active_item.get("type", -1)
	var grid_size: Vector2i = active_item.get("grid_size", Vector2i(4, 4))
	if item_type == 0:
		grid_size = Vector2i(4, 4)

	var mouse_pos := get_global_mouse_position()
	var found_cell := Vector2i(-99999, -99999)
	var found_sub := Vector2i(0, 0)

	for tile_data in _cached_tiles:
		var rel: Vector2 = mouse_pos - tile_data["top"]
		if (absf(rel.x) / 32.0) + (absf(rel.y) / 16.0) <= 1.0:
			found_cell = tile_data["cell"]
			var raw_sub := GridData.world_to_sub_cell(mouse_pos, found_cell)
			if grid_size == Vector2i(4, 4):
				found_sub = Vector2i.ZERO
			elif grid_size == Vector2i(2, 2) and snap_2x2_to_quadrants:
				# 2x2 象限对齐 (0或2, 0或2)，将大格平分4份
				found_sub = Vector2i((raw_sub.x / 2) * 2, (raw_sub.y / 2) * 2)
			else:
				# 1x1 自由选择任意微格 (0~3, 0~3)，其他尺寸边界裁剪
				found_sub = Vector2i(clampi(raw_sub.x, 0, 4 - grid_size.x), clampi(raw_sub.y, 0, 4 - grid_size.y))
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

	var grid_size: Vector2i = active_item.get("grid_size", Vector2i(4, 4))
	if item_type == 0:
		grid_size = Vector2i(4, 4)

	var is_full_cell: bool = (grid_size == Vector2i(4, 4))

	# 1. 绘制所有周围有效大格的外边框线（利用 IsoGridDrawer 极速合批，周围格子一律不画微格小点）
	var tops: Array = []
	for tile_data in _cached_tiles:
		tops.append(tile_data["top"])
	IsoGridDrawer.draw_tiles_borders(self, tops, Color(1.0, 1.0, 1.0, 0.15), 1.0)

	# 2. 当前鼠标所指的大格 (target_cell) 专属微格与高亮展示
	if target_cell != Vector2i(-99999, -99999):
		var target_floor := GridData.get_highest_floor(target_cell)
		var t_center := GridData.cell_to_world(target_cell) + Vector2(0.0, GridData.get_floor_pixel_offset(target_floor))

		# A. 微格提示：只有手持微格物体（1x1、2x2 等非整格）时，才只在当前鼠标所指的大格内部绘制微槽位小点！
		if not is_full_cell:
			var occupancies := GridData.get_cell_sub_occupancies(target_cell)
			var green_dots := PackedVector2Array()
			var red_dots := PackedVector2Array()

			for sy in 4:
				for sx in 4:
					var sp := Vector2i(sx, sy)
					# 若当前微槽位落在高亮光标覆盖范围内，跳过绘制以避免颜色重叠干扰
					var is_in_cursor := (sx >= target_sub_cell.x and sx < target_sub_cell.x + grid_size.x
									and sy >= target_sub_cell.y and sy < target_sub_cell.y + grid_size.y)
					if is_in_cursor:
						continue
					var sub_center := t_center + GridData.sub_cell_to_local_offset(sp, Vector2i(1, 1))
					if occupancies[sy * 4 + sx]:
						red_dots.push_back(sub_center + Vector2(-1, 0))
						red_dots.push_back(sub_center + Vector2(1, 0))
					else:
						green_dots.push_back(sub_center + Vector2(-1, 0))
						green_dots.push_back(sub_center + Vector2(1, 0))

			if not green_dots.is_empty():
				draw_multiline(green_dots, Color(0.2, 1.0, 0.4, 0.45), 1.0)
			if not red_dots.is_empty():
				draw_multiline(red_dots, Color(1.0, 0.25, 0.25, 0.65), 1.0)

		# B. 统一绘制当前目标高亮菱形 (支持 1x1 小麦、2x2 灌木、4x4 大树/瓷砖等所有尺寸)
		var is_occ := GridData.is_slot_occupied(target_cell, target_sub_cell, grid_size)
		var h_color: Color
		if is_full_cell:
			# 整格大物体/瓷砖：占用呈半透明红，可放呈半透明淡黄
			h_color = Color(1.0, 0.2, 0.2, 0.4) if is_occ else Color(1.0, 1.0, 0.0, 0.4)
		else:
			# 1x1 或 2x2 微格物体：占用呈半透明红，可放呈半透明翠绿
			h_color = Color(1.0, 0.2, 0.2, 0.5) if is_occ else Color(0.2, 1.0, 0.4, 0.6)

		var sub_c := t_center + GridData.sub_cell_to_local_offset(target_sub_cell, grid_size)
		var hw := float(grid_size.x) * 8.0
		var hh := float(grid_size.y) * 4.0
		IsoGridDrawer.draw_diamond(self, sub_c, hw, hh, h_color, Color(1.0, 1.0, 1.0, 0.9), 1.0)
