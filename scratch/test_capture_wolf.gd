extends SceneTree

func _init():
	var root := Node2D.new()
	get_root().add_child(root)

	var wolf_scene = load("res://scene/bio/wolf/wolf.tscn")
	var wolf = wolf_scene.instantiate()
	wolf.position = Vector2(100, 100)
	root.add_child(wolf)

	wolf.set_aim_highlight(true, Color(0.2, 1.0, 0.4, 1.0), 1.0)

	# 等待渲染一帧
	await process_frame
	await process_frame

	var img := get_root().get_viewport().get_texture().get_image()
	if img:
		img.save_png("scratch/wolf_render_test.png")
		print("Saved screenshot to scratch/wolf_render_test.png, size: ", img.get_size())
	else:
		print("Failed to get image")

	wolf.queue_free()
	root.queue_free()
	quit()

