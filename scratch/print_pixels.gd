extends SceneTree

func _init():
	var img := Image.load_from_file("scratch/test_fixed_outline.png")
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			if c != img.get_pixel(0, 0):
				print("Pixel at (", x, ", ", y, "): ", c)
	quit()

