extends SceneTree

func _init():
	var img := Image.load_from_file("scratch/wolf_render_test.png")
	var bounds_min := Vector2i(999, 999)
	var bounds_max := Vector2i(-1, -1)
	var count := 0
	var clear_col := img.get_pixel(0, 0)
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			if c != clear_col:
				count += 1
				bounds_min.x = mini(bounds_min.x, x)
				bounds_min.y = mini(bounds_min.y, y)
				bounds_max.x = maxi(bounds_max.x, x)
				bounds_max.y = maxi(bounds_max.y, y)
	print("Clear col: ", clear_col)
	print("Non-clear pixel count: ", count)
	print("Bounds: ", bounds_min, " to ", bounds_max)
	quit()

