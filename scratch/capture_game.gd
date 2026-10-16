extends Node2D

func _ready() -> void:
	var main_scene = load("res://scene/main_scene.tscn").instantiate()
	add_child(main_scene)

	for i in range(15):
		await get_tree().process_frame

	var img = get_viewport().get_texture().get_image()
	img.save_png("res://scratch/game_render_capture.png")
	print("SUCCESS: Saved capture to scratch/game_render_capture.png, size=", img.get_size())
	get_tree().quit()

