extends SceneTree

func _init():
	var wolf_scene = load("res://scene/bio/wolf/wolf.tscn")
	var wolf = wolf_scene.instantiate()
	wolf.position = Vector2(277, 168)
	get_root().add_child(wolf)
	
	var sprite: AnimatedSprite2D = wolf.find_child("AnimatedSprite2D", true, false)
	print("Sprite: ", sprite)
	var local_rect: Rect2 = sprite.get_rect()
	print("Sprite local rect: ", local_rect)
	
	# 测试狼身体上的点 (277, 148) -> y=-20
	var test_body := Vector2(277, 148)
	var local_pos := sprite.to_local(test_body)
	print("test_body local_pos: ", local_pos)
	print("has_point(test_body): ", local_rect.has_point(local_pos))
	
	# 测试狼头顶外的点 (277, 100) -> y=-68
	var test_far := Vector2(277, 100)
	print("has_point(test_far): ", local_rect.has_point(sprite.to_local(test_far)))
	
	wolf.queue_free()
	quit()

