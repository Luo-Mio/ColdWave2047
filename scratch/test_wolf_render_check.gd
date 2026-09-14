extends SceneTree

func _init():
	var root := Node2D.new()
	get_root().add_child(root)

	var wolf_scene = load("res://scene/bio/wolf/wolf.tscn")
	var wolf = wolf_scene.instantiate()
	wolf.position = Vector2(100, 100)
	root.add_child(wolf)

	var sp: AnimatedSprite2D = wolf.find_child("AnimatedSprite2D", true, false)
	print("Wolf sprite material: ", sp.material)
	print("Wolf sprite frames: ", sp.sprite_frames != null)
	
	wolf.set_aim_highlight(true, Color(0.2, 1.0, 0.4, 1.0), 1.0)
	print("After set_aim_highlight(true):")
	print("is_targeted: ", sp.get_instance_shader_parameter("is_targeted"))
	print("outline_color: ", sp.get_instance_shader_parameter("outline_color"))
	print("outline_width: ", sp.get_instance_shader_parameter("outline_width"))

	wolf.queue_free()
	root.queue_free()
	quit()

