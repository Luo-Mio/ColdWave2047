extends SceneTree

func _init() -> void:
	var main_scene = load("res://scene/main_scene.tscn").instantiate()
	root.add_child(main_scene)
	
	var gd = root.get_node("GridData")
	var player = main_scene.get_node("sortworld/CharacterBody2D")
	var cell: Vector2i = gd.world_to_cell(player.global_position)
	var fl: int = gd.get_highest_floor(cell)
	print("Player pos = ", player.global_position)
	print("Player cell = ", cell)
	print("Player highest floor = ", fl)
	
	# Check cells around player
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var c := cell + Vector2i(dx, dy)
			var f: int = gd.get_highest_floor(c)
			if f > 0:
				print("Cell ", c, " has floor ", f)
				
	quit(0)

