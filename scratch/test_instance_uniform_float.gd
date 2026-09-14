extends SceneTree

func _init():
	var shader = Shader.new()
	shader.code = """
	shader_type canvas_item;
	instance uniform bool is_targeted = false;
	instance uniform vec4 outline_color : source_color = vec4(0.2, 1.0, 0.4, 1.0);
	instance uniform float outline_width = 1.0;
	void fragment() {
		COLOR = texture(TEXTURE, UV);
	}
	"""
	var mat = ShaderMaterial.new()
	mat.shader = shader
	var s = Sprite2D.new()
	s.material = mat
	s.set_instance_shader_parameter("outline_width", 1.5)
	print("outline_width: ", s.get_instance_shader_parameter("outline_width"))
	s.free()
	quit()

