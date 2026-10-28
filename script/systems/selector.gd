# selector.gd —— 2D 等距 4x4 微网格智能交互光标
class_name Selector
extends Node2D

const IsoGridDrawer := preload("res://script/systems/iso_grid_drawer.gd")

@export var interaction_range: int = 3 # 放置交互范围半径 (网格步数)
@export var snap_2x2_to_quadrants: bool = true # 2x2 物体是否对齐到 4 个象限

var target_cell: Vector2i = Vector2i(-99999, -99999)
var target_sub_cell: Vector2i = Vector2i.ZERO

var _cached_range_centers: Array[Vector2] = []
var _last_player_cell: Vector2i = Vector2i(-99999, -99999)
var _last_target_cell: Vector2i = Vector2i(-99999, -99999)
var _last_target_sub_cell: Vector2i = Vector2i(-1, -1)

var player: Node2D = null
var inventory: InventoryComponent = null

func _ready() -> void:
	z_index = 100 # 始终在最上层绘制选框

func _process(_delta: float) -> void:
	_ensure_references()
	_update_selection()

func force_update() -> void:
	_last_target_cell = Vector2i(-99999, -99999)
	_last_player_cell = Vector2i(-99999, -99999)
	queue_redraw()

func _ensure_references() -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player") as Node2D
		if player:
			inventory = player.find_child("InventoryComponent", true, false) as InventoryComponent
			if inventory and not inventory.active_slot_changed.is_connected(_on_active_slot_changed):
				inventory.active_slot_changed.connect(_on_active_slot_changed)

func _on_active_slot_changed(_index: int, _item: Dictionary) -> void:
	force_update()

func _rebuild_range_cache(p_cell: Vector2i) -> void:
	_cached_range_centers.clear()
	var rx := interaction_range + 1
	var ry := interaction_range * 2 + 1
	for dy in range(-ry, ry + 1):
		for dx in range(-rx, rx + 1):
			var c := p_cell + Vector2i(dx, dy)
			if not GridData.has_ground_tile(c):
				continue
			var delta := c - p_cell
			var dist := absf(delta.x) + absf(delta.y) * 0.5
			if dist <= float(interaction_range) + 0.2:
				_cached_range_centers.append(GridData.cell_to_world(c))

func _update_selection() -> void:
	if player == null or inventory == null:
		return

	var p_cell := GridData.world_to_cell(player.global_position)
	if p_cell != _last_player_cell:
		_last_player_cell = p_cell
		_rebuild_range_cache(p_cell)

	var active_item := inventory.get_active_item()
	var itype: int = active_item.get("type", 0)
	# 只有手持 TILE(1), SURF(2), OBJECT(3) 时才激活放置光标
	if itype != 1 and itype != 2 and itype != 3:
		if target_cell != Vector2i(-99999, -99999):
			target_cell = Vector2i(-99999, -99999)
			queue_redraw()
		return

	var mouse_world := get_global_mouse_position()
	var hovered_cell := GridData.world_to_cell(mouse_world)

	# 检查是否在交互距离内且存在地面
	var delta := hovered_cell - p_cell
	var dist := absf(delta.x) + absf(delta.y) * 0.5
	if dist > float(interaction_range) + 0.2 or not GridData.has_ground_tile(hovered_cell):
		hovered_cell = Vector2i(-99999, -99999)

	var hovered_sub := Vector2i.ZERO
	if hovered_cell != Vector2i(-99999, -99999):
		var grid_size: Vector2i = active_item.get("grid_size", Vector2i(4, 4))
		if itype == 1 or itype == 2:
			grid_size = Vector2i(4, 4)
		
		var raw_sub := GridData.world_to_sub_cell(mouse_world, hovered_cell)
		if grid_size == Vector2i(4, 4):
			hovered_sub = Vector2i.ZERO
		elif grid_size == Vector2i(2, 2) and snap_2x2_to_quadrants:
			hovered_sub = Vector2i((raw_sub.x / 2) * 2, (raw_sub.y / 2) * 2)
		else:
			hovered_sub = Vector2i(clampi(raw_sub.x, 0, 4 - grid_size.x), clampi(raw_sub.y, 0, 4 - grid_size.y))

	target_cell = hovered_cell
	target_sub_cell = hovered_sub

	if target_cell != _last_target_cell or target_sub_cell != _last_target_sub_cell:
		_last_target_cell = target_cell
		_last_target_sub_cell = target_sub_cell
		queue_redraw()

func _draw() -> void:
	if inventory == null or target_cell == Vector2i(-99999, -99999):
		return

	var active_item := inventory.get_active_item()
	var itype: int = active_item.get("type", 0)
	if itype != 1 and itype != 2 and itype != 3:
		return

	var grid_size: Vector2i = active_item.get("grid_size", Vector2i(4, 4))
	if itype == 1 or itype == 2:
		grid_size = Vector2i(4, 4)

	var is_full_cell := (grid_size == Vector2i(4, 4))

	# 1. 绘制有效操作范围的淡白色网格底线
	IsoGridDrawer.draw_tiles_borders(self, _cached_range_centers, Color(1.0, 1.0, 1.0, 0.15), 1.0)

	var cell_center := GridData.cell_to_world(target_cell)

	# 2. 如果手持微格物体（如 1x1 小麦），在鼠标大格内绘制 16 个微槽位点
	if not is_full_cell:
		var occupancies := GridData.get_cell_sub_occupancies(target_cell)
		var green_dots := PackedVector2Array()
		var red_dots := PackedVector2Array()

		for sy in 4:
			for sx in 4:
				var sp := Vector2i(sx, sy)
				# 若微格在当前选框覆盖范围内则跳过微点，由外框高亮表现
				var in_cursor := (sx >= target_sub_cell.x and sx < target_sub_cell.x + grid_size.x
								and sy >= target_sub_cell.y and sy < target_sub_cell.y + grid_size.y)
				if in_cursor:
					continue
				var sub_pos := cell_center + GridData.sub_cell_to_local_offset(sp, Vector2i(1, 1))
				if occupancies[sy * 4 + sx]:
					red_dots.push_back(sub_pos + Vector2(-1, 0))
					red_dots.push_back(sub_pos + Vector2(1, 0))
				else:
					green_dots.push_back(sub_pos + Vector2(-1, 0))
					green_dots.push_back(sub_pos + Vector2(1, 0))

		if not green_dots.is_empty():
			draw_multiline(green_dots, Color(0.2, 1.0, 0.4, 0.5), 1.0)
		if not red_dots.is_empty():
			draw_multiline(red_dots, Color(1.0, 0.25, 0.25, 0.7), 1.0)

	# 3. 绘制目标选区菱形 (微格或整格)
	var is_occ := GridData.is_slot_occupied(target_cell, target_sub_cell, grid_size)
	var sub_center := cell_center + GridData.sub_cell_to_local_offset(target_sub_cell, grid_size)
	var half_w := float(grid_size.x) * 8.0
	var half_h := float(grid_size.y) * 4.0

	var fill_color: Color
	if is_occ:
		fill_color = Color(1.0, 0.2, 0.2, 0.45) # 占用：半透明红
	else:
		fill_color = Color(0.2, 1.0, 0.4, 0.55) if not is_full_cell else Color(1.0, 1.0, 0.2, 0.45) # 可放：翠绿或浅金

	IsoGridDrawer.draw_diamond(self, sub_center, half_w, half_h, fill_color, Color(1.0, 1.0, 1.0, 0.9), 1.0)
