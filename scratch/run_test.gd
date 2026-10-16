extends Node

func _ready() -> void:
	var main_scene = load("res://scene/main_scene.tscn").instantiate()
	add_child(main_scene)
	for i in range(5):
		await get_tree().physics_frame

	var trm: TerrainRenderManager = main_scene.get_node("TerrainRenderManager")
	var l0: TileMapLayer = GridData.layers[0]
	var surf0: TileMapLayer = main_scene.get_node("layers/surf1")

	print("=== Test 41x41 Sampling without Visual Culling ===")
	print("trm.cull_terrain_visuals: ", trm.cull_terrain_visuals)
	print("trm.sample_radius: ", trm.sample_radius)
	print("l0 used cells count: ", l0.get_used_cells().size())
	if surf0:
		print("surf0 used cells count: ", surf0.get_used_cells().size())
	print("trm.rendered_cells count: ", trm.rendered_cells.size())

	var high_cells = trm.get_high_cells(0)
	print("trm.get_high_cells(0) count: ", high_cells.size())

	# Capture a screenshot to verify full map rendering
	for i in range(10):
		await get_tree().process_frame

	var img = get_viewport().get_texture().get_image()
	img.save_png("res://scratch/full_map_41x41_capture.png")
	print("Saved full map capture to scratch/full_map_41x41_capture.png")

	get_tree().quit()
