extends Node2D

func _ready():
	var sp1 := Sprite2D.new()
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	sp1.texture = ImageTexture.create_from_image(img)
	sp1.position = Vector2(20, 20)
	add_child(sp1)

	var s_instance := Shader.new()
	s_instance.code = """
	shader_type canvas_item;
	instance uniform vec4 my_color : source_color = vec4(0.0, 0.0, 1.0, 1.0);
	void fragment() {
		COLOR = my_color;
	}
	"""
	var m1 := ShaderMaterial.new()
	m1.shader = s_instance
	sp1.material = m1
	sp1.set_instance_shader_parameter("my_color", Color(1.0, 0.0, 0.0, 1.0)) # 设为红色！

	# 测试另一个用普通的 uniform
	var sp2 := Sprite2D.new()
	sp2.texture = ImageTexture.create_from_image(img)
	sp2.position = Vector2(60, 20)
	add_child(sp2)

	var s_uniform := Shader.new()
	s_uniform.code = """
	shader_type canvas_item;
	uniform vec4 my_color : source_color = vec4(0.0, 0.0, 1.0, 1.0);
	void fragment() {
		COLOR = my_color;
	}
	"""
	var m2 := ShaderMaterial.new()
	m2.shader = s_uniform
	sp2.material = m2
	m2.set_shader_parameter("my_color", Color(0.0, 1.0, 0.0, 1.0)) # 设为绿色！

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var vp_img := get_viewport().get_texture().get_image()
	vp_img.save_png("scratch/test_uniform_compare.png")

	var c_sp1 := vp_img.get_pixel(20, 20)
	var c_sp2 := vp_img.get_pixel(60, 20)
	print("sp1 (instance uniform, expect RED): ", c_sp1)
	print("sp2 (regular uniform, expect GREEN): ", c_sp2)
	get_tree().quit()

