extends Node2D

func _ready():
	var sp := Sprite2D.new()
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in range(8, 24):
		for x in range(8, 24):
			img.set_pixel(x, y, Color(1, 1, 1, 1))
	sp.texture = ImageTexture.create_from_image(img)
	sp.position = Vector2(40, 40)
	add_child(sp)

	var shader := Shader.new()
	shader.code = """
	shader_type canvas_item;
	instance uniform bool is_targeted = false;
	instance uniform vec4 outline_color : source_color = vec4(0.2, 1.0, 0.4, 1.0);
	instance uniform float outline_width = 1.0;
	void fragment() {
		vec4 col = COLOR;
		if (is_targeted && col.a <= 0.01) {
			vec2 size = TEXTURE_PIXEL_SIZE * outline_width;
			float max_a = 0.0;
			max_a = max(max_a, texture(TEXTURE, UV + vec2(size.x, 0.0)).a);
			max_a = max(max_a, texture(TEXTURE, UV - vec2(size.x, 0.0)).a);
			max_a = max(max_a, texture(TEXTURE, UV + vec2(0.0, size.y)).a);
			max_a = max(max_a, texture(TEXTURE, UV - vec2(0.0, size.y)).a);
			if (max_a > 0.01) {
				col = outline_color;
			}
		}
		COLOR = col;
	}
	"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	sp.material = mat
	sp.set_instance_shader_parameter("is_targeted", true)
	sp.set_instance_shader_parameter("outline_color", Color(0.2, 1.0, 0.4, 1.0))
	sp.set_instance_shader_parameter("outline_width", 1.0)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var vp_img := get_viewport().get_texture().get_image()
	vp_img.save_png("scratch/test_fixed_outline.png")

	var green_count := 0
	for y in range(vp_img.get_height()):
		for x in range(vp_img.get_width()):
			var c := vp_img.get_pixel(x, y)
			if c.g > 0.8 and c.r < 0.4:
				green_count += 1
	print("RESULT -> Green outline pixel count: ", green_count)
	get_tree().quit()

