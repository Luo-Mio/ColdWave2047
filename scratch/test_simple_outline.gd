extends SceneTree

func _init():
	var root := Node2D.new()
	get_root().add_child(root)

	var sp := Sprite2D.new()
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	# 在中心画一个 16x16 的白色实心块
	for y in range(8, 24):
		for x in range(8, 24):
			img.set_pixel(x, y, Color(1, 1, 1, 1))
	sp.texture = ImageTexture.create_from_image(img)
	sp.position = Vector2(50, 50)
	sp.material = load("res://resources/materials/creature_outline.tres")
	root.add_child(sp)

	sp.set_instance_shader_parameter("is_targeted", true)
	sp.set_instance_shader_parameter("outline_color", Color(0.2, 1.0, 0.4, 1.0))
	sp.set_instance_shader_parameter("outline_width", 1.0)

	# 等待渲染
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

	var vp_img := get_root().get_viewport().get_texture().get_image()
	vp_img.save_png("scratch/outline_test.png")
	print("Saved to scratch/outline_test.png")

	var outline_count := 0
	for y in range(vp_img.get_height()):
		for x in range(vp_img.get_width()):
			var c := vp_img.get_pixel(x, y)
			if c.g > 0.8 and c.r < 0.4:
				outline_count += 1
	print("Green outline pixel count: ", outline_count)

	sp.free()
	root.free()
	quit()

