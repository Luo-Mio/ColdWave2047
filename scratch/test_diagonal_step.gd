extends SceneTree

func _init() -> void:
	print("--- Running Diagonal Step Verification Test ---")
	var root_node = root
	
	# Instantiate main scene to load GridData and tile layers
	var main_scene = load("res://scene/main_scene.tscn").instantiate()
	root_node.add_child(main_scene)
	
	var grid: Node = root_node.get_node_or_null("GridData")
	if grid == null:
		print("ERROR: GridData not found in root")
		quit(1)
		return
	
	# Setup two diagonally adjacent test cells:
	# Let cell A = (10, 10), cell B = (11, 10) (horizontal diagonal: abs(dx)==1, dy==0)
	var cell_A := Vector2i(10, 10)
	var cell_B := Vector2i(11, 10)
	
	# Flank cells around their shared vertex:
	var pos_A: Vector2 = grid.cell_to_world(cell_A)
	var pos_B: Vector2 = grid.cell_to_world(cell_B)
	var shared_vertex: Vector2 = (pos_A + pos_B) * 0.5
	
	# Set pillar A height = 5
	for z in range(0, 6):
		grid.set_tile(cell_A, z, true)
	
	# Set pillar B height = 4
	for z in range(0, 5):
		grid.set_tile(cell_B, z, true)
		
	var h_A: int = grid.get_highest_floor(cell_A)
	var h_B: int = grid.get_highest_floor(cell_B)
	print("Pillar A (10, 10) height: %d, Pillar B (11, 10) height: %d" % [h_A, h_B])
	assert(h_A == 5, "Pillar A should be 5")
	assert(h_B == 4, "Pillar B should be 4")
	
	# Test check_diagonal_bridge at the vertex between A and B
	var br: Dictionary = grid.check_diagonal_bridge(shared_vertex)
	print("Bridge at shared vertex: has_bridge = %s, floor = %d, type = %s" % [br.has_bridge, br.floor, br.type])
	assert(br.has_bridge == true, "Bridge must be detected between diagonally adjacent 5 and 4 pillars!")
	
	# Test HeightStepLimitComponent
	var comp := HeightStepLimitComponent.new()
	comp.grid_override = grid
	
	# Simulate moving from A (5) towards B (4)
	var vel_to_B: Vector2 = (pos_B - pos_A).normalized() * 100.0
	var constrained_vel: Vector2 = comp.constrain_velocity(shared_vertex - Vector2(2, 0), vel_to_B, 0.016)
	print("Constrained velocity moving towards 4-high pillar: %s (original: %s)" % [constrained_vel, vel_to_B])
	assert(constrained_vel.length() > 50.0, "Velocity should NOT be zeroed when moving towards 4-high pillar!")
	
	# Simulate moving from 5-high pillar towards a 0-high void cell
	var void_cell := Vector2i(10, 12) # vertically diagonal, height 0
	var pos_void: Vector2 = grid.cell_to_world(void_cell)
	var vel_to_void: Vector2 = (pos_void - pos_A).normalized() * 100.0
	var blocked_vel: Vector2 = comp.constrain_velocity(pos_A + Vector2(0, 14), vel_to_void, 0.016)
	print("Constrained velocity moving towards 0-high void: %s" % [blocked_vel])
	assert(blocked_vel == Vector2.ZERO or blocked_vel.dot(vel_to_void) <= 0.001, "Falling to void height 0 from height 5 must be blocked!")
	
	print("--- ALL DIAGONAL STEP TESTS PASSED SUCCESSFULLY! ---")
	quit(0)

