extends SceneTree

func get_dual_corners(u: int, v: int) -> Dictionary:
	var is_odd = (absi(v) % 2 == 1)
	if is_odd:
		return {
			"T": Vector2i(u, v - 2),
			"R": Vector2i(u + 1, v - 1),
			"B": Vector2i(u, v),
			"L": Vector2i(u, v - 1),
		}
	else:
		return {
			"T": Vector2i(u, v - 2),
			"R": Vector2i(u, v - 1),
			"B": Vector2i(u, v),
			"L": Vector2i(u - 1, v - 1),
		}

func get_affected_dual_cells(cell: Vector2i) -> Array[Vector2i]:
	var is_odd = (absi(cell.y) % 2 == 1)
	if is_odd:
		return [
			Vector2i(cell.x, cell.y),         # cell is B
			Vector2i(cell.x, cell.y + 2),     # cell is T
			Vector2i(cell.x, cell.y + 1),     # cell is R
			Vector2i(cell.x + 1, cell.y + 1), # cell is L
		]
	else:
		return [
			Vector2i(cell.x, cell.y),         # cell is B
			Vector2i(cell.x, cell.y + 2),     # cell is T
			Vector2i(cell.x - 1, cell.y + 1), # cell is R
			Vector2i(cell.x, cell.y + 1),     # cell is L
		]

func _init():
	print("--- VERIFYING DUAL CORNER MAPPING ---")
	# Test both even and odd cells
	for test_cell in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(2, 4), Vector2i(-1, 3)]:
		var affected = get_affected_dual_cells(test_cell)
		print("\nFor primary cell %s:" % [test_cell])
		for d in affected:
			var corners = get_dual_corners(d.x, d.y)
			var matched = []
			for k in corners.keys():
				if corners[k] == test_cell:
					matched.append(k)
			print("  dual cell %s has primary cell %s as: %s" % [d, test_cell, matched])
			assert(matched.size() == 1, "Must match exactly 1 corner!")
	print("\nALL DUAL CORNER MAPPINGS VERIFIED PERFECTLY!")
	quit()

