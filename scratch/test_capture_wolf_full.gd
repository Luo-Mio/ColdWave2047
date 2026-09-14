extends Node2D

func _ready():
	var wolf_scene = load("res://scene/bio/wolf/wolf.tscn")
	var wolf = wolf_scene.instantiate()
	wolf.position = Vector2(200, 200)
	add_child(wolf)

	wolf.set_aim_highlight(true, Color(0.2, 1.0, 0.4, 1.0), 1.0)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var vp_img := get_viewport().get_texture().get_image()
	vp_img.save_png("scratch/wolf_fixed_render.png")

	var green_outline_count := 0
	for y in range(vp_img.get_height()):
		for x in range(vp_img.get_width()):
			var c := vp_img.get_pixel(x, y)
			# 过滤掉头顶血条 (血条在 y < 180)
			if y > 185 and c.g > 0.8 and c.r < 0.4:
				green_outline_count += 1
	print("RESULT -> Wolf green outline pixel count: ", green_outline_count)
	get_tree().quit()

