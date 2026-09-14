extends SceneTree

func _init():
	var root := Node2D.new()
	get_root().add_child(root)

	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.6, 0.4, 0.8, 1.0))
	var tex := ImageTexture.create_from_image(img)

	# 1. 正常无 Shader 的 Sprite
	var s1 := Sprite2D.new()
	s1.texture = tex
	s1.position = Vector2(8, 8)
	vp.add_child(s1)

	await create_timer(0.05).timeout
	var vp_img := vp.get_texture().get_image()
	var c1 := vp_img.get_pixel(8, 8)
	print("Normal sprite without shader pixel color: ", c1)

	# 2. 有 creature_outline.gdshader 的 Sprite
	var mat := load("res://resources/materials/creature_outline.tres") as ShaderMaterial
	s1.material = mat
	await create_timer(0.05).timeout
	vp_img = vp.get_texture().get_image()
	var c2 := vp_img.get_pixel(8, 8)
	print("Sprite with creature_outline shader pixel color: ", c2)

	root.queue_free()
	quit()

