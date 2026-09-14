@tool
extends SceneTree

const AimPixelDrawer = preload("res://script/systems/aim_pixel_drawer.gd")

class MockGrid:
	var tile_set_data: Dictionary = {}
	# Map: cell (1, 0) is a high wall of floor 2
	# All other cells between -5 and 5 are floor 0
	func has_any_tile(cell: Vector2i) -> bool:
		return absi(cell.x) <= 5 and absi(cell.y) <= 5

	func get_highest_floor(cell: Vector2i) -> int:
		if cell == Vector2i(1, 0):
			return 2 # High wall!
		return 0     # Base floor

	func get_floor_pixel_offset(fl: int) -> float:
		return -float(fl) * 16.0

	func cell_to_world(cell: Vector2i) -> Vector2:
		return Vector2((cell.x - cell.y) * 32.0, (cell.x + cell.y) * 16.0)

	func world_to_cell(pos: Vector2) -> Vector2i:
		var u := (pos.x / 32.0 + pos.y / 16.0) * 0.5
		var v := (pos.y / 16.0 - pos.x / 32.0) * 0.5
		return Vector2i(int(floor(u + 0.001)), int(floor(v + 0.001)))

class MockAimController extends Node:
	# Pretend points with x > 40.0 are occluded by wall
	func is_point_occluded(screen_pt: Vector2, _point_z: float) -> bool:
		return screen_pt.x >= 40.0 and screen_pt.x <= 70.0

class RecordingCanvas extends Node2D:
	var drawn_polylines: Array = []
	var drawn_colors: Array = []

	@warning_ignore("native_method_override")
	func draw_polyline(points: PackedVector2Array, color: Color, _width: float = -1.0, _antialiased: bool = false) -> void:
		drawn_polylines.append(points)
		drawn_colors.append(color)

func _init() -> void:
	print("=== Running Ground Ray Adaptive Truncation & Occlusion Test ===")
	var grid := MockGrid.new()
	var ctrl := MockAimController.new()
	var canvas := RecordingCanvas.new()

	# Player is at (0, 0) on floor 0.
	# Target is at (96, 48) on floor 0 (crossing cell (1, 0)).
	var p_start := Vector2(0.0, 0.0)
	var p_end := Vector2(96.0, 48.0)
	var base_col := Color(0.2, 1.0, 0.5, 0.8)

	AimPixelDrawer.draw_terrain_adaptive_ground_ray(
		canvas, p_start, p_end, 0,
		base_col, ctrl, grid,
		0.5, true, 1.0, p_start
	)

	print("Total polylines drawn: ", canvas.drawn_polylines.size())
	for idx in range(canvas.drawn_polylines.size()):
		var pts: PackedVector2Array = canvas.drawn_polylines[idx]
		var col: Color = canvas.drawn_colors[idx]
		print("  Segment %d: %d points from %s to %s, alpha=%.3f" % [
			idx, pts.size(), str(pts[0]), str(pts[-1]), col.a
		])

	# We expect:
	# Segment 1: from start up to the front face of cell (1, 0) (unoccluded, alpha ~ 0.8)
	# Truncated gap: inside cell (1, 0)
	# Segment 2: after cell (1, 0), entering occluded shadow (alpha = 0.8 * 0.5 = 0.4)
	# Segment 3: leaving occluded shadow to end (alpha = 0.8)
	assert(canvas.drawn_polylines.size() >= 2, "Ray must be truncated into at least 2 segments by the high wall!")
	
	# Check truncation gap exists between segment 0 end and segment 1 start
	var seg0_end: Vector2 = canvas.drawn_polylines[0][-1]
	var seg1_start: Vector2 = canvas.drawn_polylines[1][0]
	var gap := (seg1_start - seg0_end).length()
	print("Truncation gap distance across high wall: %.2f px" % gap)
	assert(gap > 10.0, "High wall gap must be significantly greater than 0!")

	# Check occlusion alpha
	var has_occluded_segment := false
	for col in canvas.drawn_colors:
		if is_equal_approx(col.a, base_col.a * 0.5):
			has_occluded_segment = true
			break
	print("Has occluded segment with half alpha: ", has_occluded_segment)
	assert(has_occluded_segment, "Must have an occluded segment with half alpha behind wall!")

	print("\n>>> ALL GROUND RAY VERIFICATION TESTS PASSED CLEANLY! <<<")
	quit(0)

