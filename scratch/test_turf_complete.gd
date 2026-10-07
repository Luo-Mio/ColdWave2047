extends SceneTree

func _init():
	print("--- TESTING TURF SYSTEM INTEGRATION ---")
	
	# Instantiate TurfSystem
	var TurfSysScript = load("res://script/systems/turf_system.gd")
	var turf_sys = TurfSysScript.new()
	
	# Create dummy main scene hierarchy
	var root_node = Node2D.new()
	var sort_world = Node2D.new()
	var layers_node = Node2D.new()
	root_node.add_child(sort_world)
	root_node.add_child(layers_node)
	root_node.add_child(turf_sys)
	
	# Add a dummy layer1
	var layer1 = TileMapLayer.new()
	layer1.name = "layer1"
	layer1.tile_set = load("res://resources/surface/GreenGrass/grass_tileset.tres")
	layers_node.add_child(layer1)
	
	# Init TurfSystem
	turf_sys.init_turf_system(root_node, sort_world, layers_node)
	
	var floor0_layer = turf_sys.floor0_turf_layer
	print("Floor 0 turf layer created: ", floor0_layer != null)
	print("Floor 0 position: ", floor0_layer.position)
	assert(floor0_layer.position == Vector2(0, -16), "Position must be (0, -16)")
	
	# Test placing single turf at (0, 0)
	print("\nPlacing turf at (0, 0), z=0...")
	turf_sys.set_turf(Vector2i(0, 0), 0, true)
	
	var used_cells = floor0_layer.get_used_cells()
	print("Floor 0 used cells count: ", used_cells.size())
	for c in used_cells:
		var atlas = floor0_layer.get_cell_atlas_coords(c)
		print("  cell %s -> atlas %s" % [c, atlas])
	
	assert(used_cells.size() == 4, "Should have exactly 4 dual cells for 1 turf")
	assert(floor0_layer.get_cell_atlas_coords(Vector2i(0, 0)) == Vector2i(1, 3), "Cell (0,0) must have atlas (1,3) [Bottom]")
	assert(floor0_layer.get_cell_atlas_coords(Vector2i(0, 2)) == Vector2i(3, 3), "Cell (0,2) must have atlas (3,3) [Top]")
	assert(floor0_layer.get_cell_atlas_coords(Vector2i(-1, 1)) == Vector2i(0, 2), "Cell (-1,1) must have atlas (0,2) [Right]")
	assert(floor0_layer.get_cell_atlas_coords(Vector2i(0, 1)) == Vector2i(0, 0), "Cell (0,1) must have atlas (0,0) [Left]")
	print("Single turf placement test: PASSED!")
	
	# Test placing adjacent turf at (1, 0)
	print("\nPlacing adjacent turf at (1, 0), z=0...")
	turf_sys.set_turf(Vector2i(1, 0), 0, true)
	print("Floor 0 used cells count: ", floor0_layer.get_used_cells().size())
	for c in floor0_layer.get_used_cells():
		var atlas = floor0_layer.get_cell_atlas_coords(c)
		print("  cell %s -> atlas %s" % [c, atlas])
	
	# Test erasing turf
	print("\nErasing turf at (0, 0) and (1, 0)...")
	turf_sys.set_turf(Vector2i(0, 0), 0, false)
	turf_sys.set_turf(Vector2i(1, 0), 0, false)
	print("Floor 0 used cells after erase: ", floor0_layer.get_used_cells().size())
	assert(floor0_layer.get_used_cells().size() == 0, "All dual cells should be erased")
	print("Erasing test: PASSED!")
	
	print("\nALL INTEGRATION TESTS PASSED SUCCESSFULLY!")
	quit()

