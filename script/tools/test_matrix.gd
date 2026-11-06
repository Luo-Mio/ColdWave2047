extends SceneTree

func _init():
	# Test whether MODEL_MATRIX in 2D canvas_item depends on camera position
	var vp = root
	var cam = Camera2D.new()
	vp.add_child(cam)
	cam.position = Vector2(100, 200)
	
	var node = Node2D.new()
	node.position = Vector2(50, 50)
	vp.add_child(node)
	
	print("Node global position: ", node.global_position)
	print("Node global transform: ", node.global_transform)
	print("Canvas transform (camera): ", vp.canvas_transform)
	quit(0)

