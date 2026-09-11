# fpslabel.gd —— 显示游戏运行帧率与性能监控
extends Label

# 预设可选档位：30 -> 60 -> 120 -> 144 -> 不限(0)
const FPS_PRESETS: Array[int] = [30, 60, 120, 144, 0]
var _preset_idx: int = 2 # 默认 120
 
func _ready() -> void:
	# 初始应用默认最高帧率 (120 FPS)
	Engine.max_fps = FPS_PRESETS[_preset_idx]

	# 确保在 UI 顶层
	z_index = 100
	# 舒适的左上角间距
	position = Vector2(16, 12)
	# 添加文字阴影与清晰字号，确保在任何地形或迷雾背景下都清晰可读
	add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	add_theme_constant_override("shadow_offset_x", 1)
	add_theme_constant_override("shadow_offset_y", 1)
	add_theme_constant_override("shadow_outline_size", 2)
	add_theme_font_size_override("font_size", 14)

func _process(_delta: float) -> void:
	var fps := Engine.get_frames_per_second()
	var cap_str := "不限" if Engine.max_fps == 0 else str(Engine.max_fps)
	text = "FPS: %d (上限: %s)" % [fps, cap_str]
	
	# 根据帧率高低变色指示性能健康度
	if fps >= 55:
		add_theme_color_override("font_color", Color(0.4, 1.0, 0.4, 1.0)) # 60fps 充沛：亮绿色
	elif fps >= 30:
		add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0)) # 30~55fps：金黄色
	else:
		add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0)) # <30fps 掉帧：警示红

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# 按 F3: 显隐 FPS 监控
		if event.keycode == KEY_F3:
			visible = not visible
		# 按 F4: 随时循环切换最高帧率 (30 -> 60 -> 120 -> 144 -> 不限)
		elif event.keycode == KEY_F4:
			_preset_idx = (_preset_idx + 1) % FPS_PRESETS.size()
			var target_fps := FPS_PRESETS[_preset_idx]
			Engine.max_fps = target_fps
			print("当前最高帧数限制已切换为: ", "不限" if target_fps == 0 else str(target_fps) + " FPS")
