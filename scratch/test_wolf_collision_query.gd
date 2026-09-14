extends SceneTree

func _init():
	var root = Node2D.new()
	get_root().add_child(root)
	
	var wolf_scene = load("res://scene/bio/wolf/wolf.tscn")
	var wolf = wolf_scene.instantiate()
	wolf.position = Vector2(100, 100)
	root.add_child(wolf)
	
	# 等待一帧让物理空间更新
	await create_timer(0.1).timeout
	
	var space = root.get_world_2d().direct_space_state
	var p = PhysicsPointQueryParameters2D.new()
	p.position = Vector2(100, 100)
	p.collision_mask = 4
	p.collide_with_bodies = true
	
	var res = space.intersect_point(p, 1)
	print("Point at (100, 100): ", res)
	if not res.is_empty():
		print("Collider: ", res[0].collider.name)
		print("Collider is Wolf: ", res[0].collider is Wolf)
	
	# 测试偏离点
	p.position = Vector2(100, 105)
	var res2 = space.intersect_point(p, 1)
	print("Point at (100, 105): ", res2.size())
	
	# 测试外面点
	p.position = Vector2(100, 120)
	var res3 = space.intersect_point(p, 1)
	print("Point at (100, 120): ", res3.size())
	
	wolf.queue_free()
	root.queue_free()
	quit()

