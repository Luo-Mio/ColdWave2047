extends SceneTree

func _init():
	var img := Image.load_from_file("scratch/wolf_render_test.png")
	var has_green_outline := false
	var green_pixels := []
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			# 检测是否是 outline_color (0.2, 1.0, 0.4) 附近，且不是血条 (血条在 y < 15)
			if y > 15 and c.g > 0.8 and c.r < 0.4:
				green_pixels.append(Vector2i(x, y))
	print("Found green outline pixels below health bar: ", green_pixels.size())
	if green_pixels.size() > 0:
		print("Sample green pixels: ", green_pixels.slice(0, 10))
	quit()

