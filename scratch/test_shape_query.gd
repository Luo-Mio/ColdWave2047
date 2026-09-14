extends SceneTree

func _init():
	var root = Node2D.new()
	get_root().add_child(root)
	
	var wolf_scene = load("res://scene/bio/wolf/wolf.tscn")
	var wolf = wolf_scene.instantiate()
	wolf.position = Vector2(100, 100)
	root.add_child(wolf)
	
	await create_timer(0.1).timeout
	
	var space = root.get_world_2d().direct_space_state
	var sq = PhysicsShapeQueryParameters2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 6.0
	sq.shape = circle
	sq.transform = Transform2D(0.0, Vector2(100, 114)) # 距离边界仅 2px
	sq.collision_mask = 4
	sq.collide_with_bodies = true
	
	var res = space.intersect_shape(sq, 1)
	print("Shape query at (100, 114) with r=6: ", res.size())
	if not res.is_empty():
		print("Found collider: ", res[0].collider.name)
		
	wolf.queue_free()
	root.queue_free()
	quit()

