extends SceneTree

func _init():
	var sh = Shader.new()
	sh.code = """
	shader_type canvas_item;
	void vertex() {
		vec2 root_world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
	}
	"""
	var mat = ShaderMaterial.new()
	mat.shader = sh
	var sp = Sprite2D.new()
	sp.material = mat
	sp.position = Vector2(25, 35)
	
	var cam = Camera2D.new()
	cam.position = Vector2(500, 500)
	root.add_child(cam)
	root.add_child(sp)
	
	print("Shader compiled successfully!")
	quit(0)

