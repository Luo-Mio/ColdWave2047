@tool
extends SceneTree

const AimPixelDrawer = preload("res://script/systems/aim_pixel_drawer.gd")

class MockGrid:
	var tile_set_data: Dictionary = {}
	# Map:
	# cell (1, 0) is a high wall of floor 2
	# cell (-1, 0) is a low valley of floor 0
	# All other cells are floor 1
	func has_any_tile(cell: Vector2i) -> bool:
		return absi(cell.x) <= 5 and absi(cell.y) <= 5

	func get_highest_floor(cell: Vector2i) -> int:
		if cell == Vector2i(1, 0):
			return 2 # High wall (fl = 2)
		if cell == Vector2i(-1, 0):
			return 0 # Low pit/valley (fl = 0)
		return 1     # Normal ground (fl = 1)

	func get_floor_pixel_offset(fl: int) -> float:
		return -float(fl) * 16.0

	func cell_to_world(cell: Vector2i) -> Vector2:
		return Vector2((cell.x - cell.y) * 32.0, (cell.x + cell.y) * 16.0)

	func world_to_cell(pos: Vector2) -> Vector2i:
		var u := (pos.x / 32.0 + pos.y / 16.0) * 0.5
		var v := (pos.y / 16.0 - pos.x / 32.0) * 0.5
		return Vector2i(int(floor(u + 0.001)), int(floor(v + 0.001)))

class MockAimController extends Node:
	func is_point_occluded(_screen_pt: Vector2, _point_z: float) -> bool:
		return false

class RecordingCanvas extends RefCounted:
	var drawn_polylines: Array = []
	var drawn_colors: Array = []

	func draw_polyline(points: PackedVector2Array, color: Color, _width: float = -1.0, _antialiased: bool = false) -> void:
		drawn_polylines.append(points)
		drawn_colors.append(color)

	func draw_rect(_r: Rect2, _c: Color, _filled: bool = true, _w: float = -1.0) -> void:
		pass

func _init() -> void:
	print("=== Running Ground Ray Low-Floor Unaffected & High-Floor Truncation Test ===")
	var grid := MockGrid.new()
	var ctrl := MockAimController.new()

	# -------------------------------------------------------------
	# Test 1: Player is on floor 1, aiming across cell (-1, 0) (floor 0, lower than player)
	# Requirement: When cells are lower than the character, the line is unaffected (single continuous segment)!
	# -------------------------------------------------------------
	print("\n--- Test 1: Crossing lower floor (floor 0 vs player floor 1) ---")
	var canvas_low := RecordingCanvas.new()
	var p_start := Vector2(0.0, 0.0)
	var p_end_low := Vector2(-48.0, -24.0)
	var base_col := Color(0.2, 1.0, 0.5, 0.8)

	AimPixelDrawer.draw_terrain_adaptive_ground_ray(
		canvas_low, p_start, p_end_low, 1,
		base_col, ctrl, grid,
		0.5, false, 1.0, p_start # require_same_floor = false
	)

	print("Polylines drawn across lower floor: ", canvas_low.drawn_polylines.size())
	assert(canvas_low.drawn_polylines.size() == 1, "Line across lower floor must be completely unaffected (1 continuous segment)!")
	var start_pt: Vector2 = canvas_low.drawn_polylines[0][0]
	var end_pt: Vector2 = canvas_low.drawn_polylines[0][-1]
	print("  Line drawn seamlessly across low floor from %s to %s (OK)" % [start_pt, end_pt])

	# -------------------------------------------------------------
	# Test 2: Player is on floor 1, aiming across cell (1, 0) (floor 2, higher than player)
	# Requirement: When encountering higher floor, line is truncated, then resumes!
	# -------------------------------------------------------------
	print("\n--- Test 2: Crossing higher floor (floor 2 vs player floor 1) ---")
	var canvas_high := RecordingCanvas.new()
	var p_end_high := Vector2(96.0, 48.0)

	AimPixelDrawer.draw_terrain_adaptive_ground_ray(
		canvas_high, p_start, p_end_high, 1,
		base_col, ctrl, grid,
		0.5, false, 1.0, p_start # require_same_floor = false
	)

	print("Polylines drawn across higher floor: ", canvas_high.drawn_polylines.size())
	assert(canvas_high.drawn_polylines.size() >= 2, "Line across higher floor must be truncated into at least 2 segments!")
	var seg1_first: Vector2 = canvas_high.drawn_polylines[1][0]
	var seg0_last: Vector2 = canvas_high.drawn_polylines[0][-1]
	var gap: float = (seg1_first - seg0_last).length()
	print("  High wall truncation gap: %.2f px (OK)" % gap)
	assert(gap > 10.0, "High wall gap must be significantly greater than 0!")

	print("\n>>> ALL LOW-FLOOR UNAFFECTED & HIGH-FLOOR TRUNCATION TESTS PASSED CLEANLY! <<<")
	quit(0)
