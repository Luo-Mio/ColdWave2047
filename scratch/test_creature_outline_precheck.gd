extends SceneTree

func _init():
	var img_idle: Image = Image.load_from_file("res://resources/Bio/wolf/wolf-idle.png")
	var img_run: Image = Image.load_from_file("res://resources/Bio/wolf/wolf-run.png")
	print("Wolf idle size: ", img_idle.get_size() if img_idle else "null")
	print("Wolf run size: ", img_run.get_size() if img_run else "null")
	quit()

