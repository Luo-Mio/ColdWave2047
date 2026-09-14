@tool
extends SceneTree

const IsoGridDrawer = preload("res://script/systems/iso_grid_drawer.gd")
const GridDataScript = preload("res://script/core/grid_data.gd")
const AimTerrainSolverScript = preload("res://script/systems/aim_terrain_solver.gd")
const SelectorScript = preload("res://script/systems/selector.gd")

class MockGrid:
	var tile_set_data: Dictionary = {}
	func has_any_tile(cell: Vector2i) -> bool:
		return absi(cell.x) <= 2 and absi(cell.y) <= 2
	func get_highest_floor(cell: Vector2i) -> int:
		if cell.x >= 1:
			return 2 # Cliff top at floor 2
		return 0     # Valley floor 0
	func get_floor_pixel_offset(fl: int) -> float:
		return -float(fl) * 16.0
	func cell_to_world(cell: Vector2i) -> Vector2:
		return Vector2((cell.x - cell.y) * 32.0, (cell.x + cell.y) * 16.0)
	func world_to_cell(pos: Vector2) -> Vector2i:
		var u := (pos.x / 32.0 + pos.y / 16.0) * 0.5
		var v := (pos.y / 16.0 - pos.x / 32.0) * 0.5
		return Vector2i(int(floor(u)), int(floor(v)))

class TestImpactCanvas extends Node2D:
	var grid := MockGrid.new()
	func _draw() -> void:
		# 1. Draw 3x3 on floor 2 (cliff top)
		var t0 := Time.get_ticks_usec()
		IsoGridDrawer.draw_tile_grid(self, Vector2i(1, 1), 1, 2, Color(0.4, 0.8, 1.0, 0.5), grid, 1.0)
		var t1 := Time.get_ticks_usec()
		print("3x3 Tile Grid Draw Time: ", (t1 - t0), " us")
		
		# 2. Draw diamond
		IsoGridDrawer.draw_diamond(self, Vector2(100, 100), 16.0, 8.0, Color.GREEN, Color.WHITE, 1.0)
		print("Draw diamond OK")

func _init() -> void:
	print("=== Running Impact Grid & IsoGridDrawer Verification ===")
	var canvas := TestImpactCanvas.new()
	root.add_child(canvas)
	canvas.queue_redraw()
	RenderingServer.force_draw()
	
	# Verify hit_cell in terrain solver
	print("\n--- Verifying hit_cell in AimTerrainSolver ---")
	var grid := MockGrid.new()
	var res := AimTerrainSolverScript.solve_adaptive_trajectory(
		Vector2.ZERO, 0, Vector2(0, -8),
		0.1, 0.0, 260.0, 240.0, 8.0, 24, grid
	)
	print("Adaptive Trajectory is_valid: ", res.get("is_valid"))
	print("Adaptive Trajectory hit_type: ", res.get("hit_type"))
	print("Adaptive Trajectory hit_cell: ", res.get("hit_cell"))
	print("Adaptive Trajectory hit_floor: ", res.get("hit_floor"))
	assert(res.has("hit_cell"), "res must contain hit_cell!")
	assert(res.has("hit_floor"), "res must contain hit_floor!")
	
	print("\nALL AUTOMATED VERIFICATION PASSED CLEANLY!")
	quit()
