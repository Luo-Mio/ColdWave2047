extends SceneTree

const SHADER = preload("res://script/shaders/creature_outline.gdshader")

func _init():
	var sprite = Sprite2D.new()
	var mat = ShaderMaterial.new()
	mat.shader = SHADER
	sprite.material = mat
	
	sprite.set_instance_shader_parameter("is_targeted", true)
	sprite.set_instance_shader_parameter("outline_color", Color(0.2, 1.0, 0.4, 1.0))
	
	var val_targeted = sprite.get_instance_shader_parameter("is_targeted")
	var val_color = sprite.get_instance_shader_parameter("outline_color")
	print("is_targeted = ", val_targeted)
	print("outline_color = ", val_color)
	
	sprite.free()
	quit()

