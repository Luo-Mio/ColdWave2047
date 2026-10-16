extends Node

func _ready() -> void:
	var main_scene = load("res://scene/main_scene.tscn").instantiate()
	add_child(main_scene)
	for i in range(2):
		await get_tree().physics_frame

	var l0: TileMapLayer = main_scene.get_node("layers/layer1")
	var ts = l0.tile_set
	print("TileSet tile_shape: ", ts.tile_shape, " (0=Square, 1=Isometric, 2=HalfOffsetNegative, 3=HalfOffsetPositive)")
	print("TileSet tile_layout: ", ts.tile_layout, " (0=Stacked, 1=Staggered, 2=Isometric, etc.)")
	print("TileSet tile_size: ", ts.tile_size)

	var p00 = l0.map_to_local(Vector2i(0, 0))
	var p10 = l0.map_to_local(Vector2i(1, 0))
	var p01 = l0.map_to_local(Vector2i(0, 1))
	var p11 = l0.map_to_local(Vector2i(1, 1))
	var p02 = l0.map_to_local(Vector2i(0, 2))
	print("map_to_local(0,0) = ", p00)
	print("map_to_local(1,0) = ", p10, " diff = ", p10 - p00)
	print("map_to_local(0,1) = ", p01, " diff = ", p01 - p00)
	print("map_to_local(1,1) = ", p11, " diff = ", p11 - p00)
	print("map_to_local(0,2) = ", p02, " diff = ", p02 - p00)

	var player = main_scene.get_node("sortworld/CharacterBody2D")
	var center_cell = GridData.world_to_cell(player.global_position)
	print("Player cell: ", center_cell, " pos: ", player.global_position)

	var trm = main_scene.get_node("TerrainRenderManager")
	var rendered = trm.get_rendered_cells()
	print("Rendered cells count: ", rendered.size())

	# Now check min/max offsets in grid coordinates and screen coordinates
	var min_dx = 999
	var max_dx = -999
	var min_dy = 999
	var max_dy = -999
	var min_rx = 999999.0
	var max_rx = -999999.0
	var min_ry = 999999.0
	var max_ry = -999999.0

	var center_pos = GridData.cell_to_world(center_cell)

	for c in rendered:
		var d = c - center_cell
		min_dx = mini(min_dx, d.x)
		max_dx = maxi(max_dx, d.x)
		min_dy = mini(min_dy, d.y)
		max_dy = maxi(max_dy, d.y)

		var wp = GridData.cell_to_world(c)
		var rel = wp - center_pos
		min_rx = minf(min_rx, rel.x)
		max_rx = maxf(max_rx, rel.x)
		min_ry = minf(min_ry, rel.y)
		max_ry = maxf(max_ry, rel.y)

	print("Cell delta X: [", min_dx, ", ", max_dx, "]")
	print("Cell delta Y: [", min_dy, ", ", max_dy, "]")
	print("World rel X: [", min_rx, ", ", max_rx, "]")
	print("World rel Y: [", min_ry, ", ", max_ry, "]")

	# Check the diagonals from center_cell
	# Diagonal directions on screen:
	# SE: +x, +y on screen? Or what?
	# Let's inspect along screen directions:
	# North (0, -y), South (0, +y), West (-x, 0), East (+x, 0)
	# NW (-x, -y), NE (+x, -y), SW (-x, +y), SE (+x, +y)
	
	# Let's check how many steps in each direction are in rendered:
	# In isometric projection:
	# Stepping (rel.x > 0, rel.y > 0) is Southeast.
	# Let's count how many tiles in rendered are along each diagonal:
	for dir_name in ["NW (-x, -y)", "NE (+x, -y)", "SW (-x, +y)", "SE (+x, +y)", "N (0, -y)", "S (0, +y)", "W (-x, 0)", "E (+x, 0)"]:
		pass

	get_tree().quit()

