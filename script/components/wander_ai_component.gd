# wander_ai_component.gd —— 生物随机漫步与休憩 AI 组件
class_name WanderAIComponent
extends Node

@export_group("AI 闲逛行为配置")
# 是否开启随机闲逛 (在检查器随时勾选测试)
@export var enable_wander: bool = false
# 休息时间范围 (秒)
@export var min_rest_time: float = 1.5
@export var max_rest_time: float = 4.0
# 移动概率 (0.0~1.0)
@export var move_chance: float = 0.6
# 单次移动持续时间范围 (秒)
@export var min_move_time: float = 1.0
@export var max_move_time: float = 3.0

var _timer: float = 0.0
var _current_dir: Vector2 = Vector2.ZERO
var _is_moving: bool = false

func _ready() -> void:
	_timer = randf_range(min_rest_time, max_rest_time)

# 每物理帧更新状态并返回期望的移动向量 (Vector2)
func update_ai(delta: float) -> Vector2:
	if not enable_wander:
		return Vector2.ZERO

	_timer -= delta
	if _timer <= 0.0:
		if _is_moving:
			# 走累了，停下休息
			_is_moving = false
			_current_dir = Vector2.ZERO
			_timer = randf_range(min_rest_time, max_rest_time)
		else:
			# 休息结束，根据概率决定是否移动
			if randf() <= move_chance:
				_is_moving = true
				_current_dir = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
				_timer = randf_range(min_move_time, max_move_time)
			else:
				# 继续休息一段短时间
				_timer = randf_range(min_rest_time * 0.5, max_rest_time * 0.5)

	return _current_dir

