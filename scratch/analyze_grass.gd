extends SceneTree

func _init():
	var img = Image.load_from_file("resources/surface/GreenGrass/grass_out.png")
	if img == null:
		print("ERROR: Cannot load grass_out.png")
		quit(1)
		return
	
	var lines = []
	for row in range(4):
		for col in range(4):
			var x0 = col * 64
			var y0 = row * 32
			var top_a = img.get_pixel(x0 + 32, y0 + 6).a > 0.5
			var btm_a = img.get_pixel(x0 + 32, y0 + 26).a > 0.5
			var left_a = img.get_pixel(x0 + 10, y0 + 16).a > 0.5
			var right_a = img.get_pixel(x0 + 54, y0 + 16).a > 0.5
			var center_a = img.get_pixel(x0 + 32, y0 + 16).a > 0.5
			
			lines.append("Tile (%d, %d): Center=%s | Top=%s, Right=%s, Bottom=%s, Left=%s" % [
				col, row, center_a, top_a, right_a, btm_a, left_a
			])
	var f = FileAccess.open("scratch/grass_analysis.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	quit(0)

