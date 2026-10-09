extends SceneTree

func _init() -> void:
	print("--- TEST IMAGE 1 VS IMAGE 2 IN DETAIL ---")
	
	# Load HeightStepLimitComponent
	var CompScript = load("res://script/components/height_step_limit_component.gd")
	var comp = CompScript.new()
	
	var mock_grid = Node.new()
	mock_grid.name = "GridData"
	root.add_child(mock_grid)
	
	var grid_script = GDScript.new()
	grid_script.source_code = """
extends Node
var floors = {}
func has_any_tile(cell: Vector2i) -> bool:
	return floors.has(cell)
func get_highest_floor(cell: Vector2i) -> int:
	return floors.get(cell, 0)
func world_to_cell(pos: Vector2) -> Vector2i:
	var tml = TileMapLayer.new()
	var ts = TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_size = Vector2i(64, 32)
	tml.tile_set = ts
	return tml.local_to_map(pos)
func cell_to_world(cell: Vector2i) -> Vector2:
	var tml = TileMapLayer.new()
	var ts = TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_size = Vector2i(64, 32)
	tml.tile_set = ts
	return tml.map_to_local(cell)
"""
	grid_script.reload()
	mock_grid.set_script(grid_script)
	root.add_child(comp)
	comp.grid_override = mock_grid

	# Let's reconstruct the map in the screenshot:
	# Looking at Image 1 and Image 2:
	# High ground (Floor 1) staircase:
	# There is a block at (0, 2)
	# A block at (0, 1) or (-1, 1)?
	# Let's check cell positions:
	# In isometric grid:
	# (0, 0) -> (32, 16)
	# (0, 1) -> (64, 32)
	# (0, 2) -> (32, 48)
	# (0, 3) -> (64, 64)
	# (0, 4) -> (32, 80)
	# (-1, 1) -> (0, 32)
	# (-1, 2) -> (-32, 48)
	# (-1, 3) -> (0, 64)
	
	# Notice:
	# (0, 4) at (32, 80)
	# (0, 3) at (64, 64)
	# (0, 2) at (32, 48)
	# (0, 1) at (64, 32)
	# (0, 0) at (32, 16)
	# This alternates x=32 and x=64, running vertically!
	# WAIT! Look at Image 1:
	# The blocks have centers:
	# Block 1 at (0, 3) (64, 64)
	# Block 2 at (0, 2) (32, 48)
	# Block 3 at (-1, 1) (0, 32)
	# That runs along (-32, -16) diagonal!
	# Wait, what if:
	# High blocks are at:
	# (0, 1) [64, 32], (0, 2) [32, 48], (0, 3) [64, 64]?
	# Let's test BOTH patterns:
	# Pattern A: Vertical column x=0:
	# (0, 0), (0, 1), (0, 2), (0, 3), (0, 4)... are Floor 1!
	# (and all cells with x >= 1 are Floor 1? Or x <= 0 are Floor 1?)
	
	# In Image 1:
	# The cliff is on the right! High ground extends to the top and right!
	# Let's check: If high ground is on the top-right:
	# That means:
	# (0, 0): Floor 1, (1, 0): Floor 1, (2, 0): Floor 1...
	# (0, 1): Floor 1, (1, 1): Floor 1, (2, 1): Floor 1...
	# (0, 2): Floor 1, (1, 2): Floor 1, (2, 2): Floor 1...
	# (-1, 1): Floor 0, (-1, 2): Floor 0, (-1, 3): Floor 0...
	
	print("--- TESTING VERTICAL COLUMN CLIFF (x <= 0 is low, x >= 0 is high) ---")
	var grid_map = {}
	for y in range(-5, 10):
		for x in range(-5, 10):
			# Default floor 0
			grid_map[Vector2i(x, y)] = 0
			
	# Let's set high ground matching Image 1:
	# Look at Image 1:
	# High ground has tiles:
	# (0, 1): 1, (1, 1): 1, (2, 1): 1
	# (0, 2): 1, (1, 2): 1, (2, 2): 1
	# (0, 3): 1, (1, 3): 1, (2, 3): 1
	# And to the left:
	# (-1, 1): 0, (-1, 2): 0, (-1, 3): 0...
	# Wait! In Image 1, look at the block directly in front of the character:
	# To the left of the block is lower ground.
	# To the right of the block is lower ground? Or high ground?
	# In Image 1, to the right of the block is another cliff face turning right!
	# In Image 2, there is a black hole (void) right where the character in Image 1 was!
	# LOOK AT IMAGE 2:
	# In Image 2, the tile at the bottom has a BLACK SQUARE! That tile was removed/destroyed!
	
	quit()
