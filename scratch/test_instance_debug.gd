extends SceneTree

func _init():
	var root := Node2D.new()
	get_root().add_child(root)

	var sp := Sprite2D.new()
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	sp.texture = ImageTexture.create_from_image(img)
	sp.position = Vector2(50, 50)

	var shader := Shader.new()
	shader.code = """
	shader_type canvas_item;
	instance uniform bool is_targeted = false;
	void fragment() {
		if (is_targeted) {
			COLOR = vec4(1.0, 0.0, 0.0, 1.0);
		} else {
			COLOR = vec4(0.0, 0.0, 1.0, 1.0);
		}
	}
	"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	sp.material = mat

	sp.set_instance_shader_parameter("is_targeted", true)

	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

	var vp_img := get_root().get_viewport().get_texture().get_image()
	vp_img.save_png("scratch/test_instance_check.png")

	# 检查像素颜色
	for y in range(vp_img.get_height()):
		for x in range(vp_img.get_width()):
			var c := vp_img.get_pixel(x, y)
			if c.r > 0.8 and c.b < 0.2:
				print("FOUND RED PIXEL at (", x, ", ", y, ") -> is_targeted is TRUE!")
				sp.free()
				root.free()
				quit()
			elif c.b > 0.8 and c.r < 0.2:
				print("FOUND BLUE PIXEL at (", x, ", ", y, ") -> is_targeted is FALSE!")
				sp.free()
				root.free()
				quit()

	print("NO RED OR BLUE PIXEL FOUND!")
	sp.free()
	root.free()
	quit()

