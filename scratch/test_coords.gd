extends SceneTree

func _init():
	var scene = load("res://scene/main_scene.tscn").instantiate()
	var sort_world = scene.get_node("sortworld")
	print("sort_world children count: ", sort_world.get_child_count())
	for c in sort_world.get_children():
		print("  child: ", c.name, ", type: ", c.get_class(), ", sort_key: ", c.get("sort_key"), ", layer_no: ", c.get("layer_no"))
	quit()
