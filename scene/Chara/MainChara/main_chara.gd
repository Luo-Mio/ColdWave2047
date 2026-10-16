class_name MainChara
extends Node2D

@export_group("移动控制")
## 角色移动速度 (像素/秒)
@export_range(10.0, 1500.0, 10.0) var move_speed: float = 300.0

func _process(delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	# 如果动作未映射，自动回退到 WASD 按键检测
	if input_vector == Vector2.ZERO:
		var x := 0.0
		var y := 0.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			x += 1.0
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			y -= 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			y += 1.0
		input_vector = Vector2(x, y).normalized()
	
	if input_vector != Vector2.ZERO:
		position += input_vector * move_speed * delta
