extends SceneTree

func _init():
	var root := Node2D.new()
	get_root().add_child(root)

	var sp := Sprite2D.new()
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 1, 1))
	sp.texture = ImageTexture.create_from_image(img)
	sp.position = Vector2(50, 50)
	root.add_child(sp)

	var shader := Shader.new()
	shader.code = """
	shader_type canvas_item;
	instance uniform bool is_targeted = false;
	void fragment() {
		if (is_targeted) {
			COLOR = vec4(1.0, 0.0, 0.0, 1.0);
		} else {
			COLOR = vec4(0.0, 1.0, 0.0, 1.0);
		}
	}
	"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	sp.material = mat

	sp.set_instance_shader_parameter("is_targeted", true)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var vp_img := get_root().get_viewport().get_texture().get_image()
	var p := vp_img.get_pixel(50, 50)
	print("Pixel at (50, 50): ", p)
	if p.r > 0.9:
		print("SUCCESS: instance uniform is_targeted is RED (TRUE)!")
	elif p.g > 0.9:
		print("FAILURE: instance uniform is_targeted is GREEN (FALSE)!")
	else:
		print("OTHER: ", p)

	sp.free()
	root.free()
	quit()

