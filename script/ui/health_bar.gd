# health_bar.gd —— 通用像素风格生命值条 UI 组件 (支持头顶悬浮与界面集成)
class_name HealthBar
extends Control

@export_group("尺寸与位置 (Size & Layout)")
## 血条内槽像素宽度 (默认 20px，适合常规生物)
@export var bar_width: float = 20.0
## 血条内槽像素高度 (默认 2px，细腻像素感)
@export var bar_height: float = 1.0
## 是否以自身原点为中心居中绘制 (设为 true 时，仅需将节点位置设为 (0, offset_y) 即可自动居中)
@export var center_origin: bool = true
## 头顶悬浮垂直偏移量 (像素，负数向上)
@export var overhead_offset_y: float = -28.0

@export_group("色彩与外观 (Colors & Aesthetics)")
## 是否绘制 1 像素黑色像素外边框
@export var show_border: bool = false
## 外边框颜色
@export var border_color: Color = Color(0.04, 0.04, 0.06, 0.95)
## 血槽底色 (受击未满血时露出的底槽)
@export var bg_color: Color = Color(0.12, 0.12, 0.15, 0.85)
## 是否启用动态血量色彩渐变 (满血绿 -> 半血黄 -> 残血红)
@export var dynamic_color: bool = true
## 默认健康状态颜色
@export var health_color: Color = Color(0.22, 0.88, 0.38, 0.95)
## 预警中等血量颜色
@export var warning_color: Color = Color(0.95, 0.78, 0.22, 0.95)
## 危险濒死血量颜色
@export var critical_color: Color = Color(0.95, 0.25, 0.25, 0.95)

@export_group("受击缓冲与残影 (Damage Catch-up)")
## 是否显示受击扣血时的延迟缓冲残影条 (经典 ARPG 黄白条停顿后追赶缩减)
@export var show_damage_catchup: bool = true
## 残影缓冲条颜色
@export var catchup_color: Color = Color(1.0, 0.85, 0.3, 0.95)
## 受击后残影开始缩减前的静止停顿时间 (秒)
@export var catchup_delay: float = 0.25
## 残影追赶动画持续时间 (秒)
@export var catchup_duration: float = 0.35

@export_group("自动渐隐与常驻控制 (Visibility & Auto-hide)")
## 是否在脱战/满血状态下自动半透明渐隐 (降低画面杂乱度)
@export var auto_hide: bool = true
## 受击或血量变动后保持常亮的时间 (秒)
@export var auto_hide_delay: float = 2.5
## 渐显与渐隐的过渡时间 (秒)
@export var fade_duration: float = 0.3

# 运行时数据
var max_health: float = 100.0
var current_health: float = 100.0

var _displayed_health: float = 100.0
var _catchup_health: float = 100.0

var _catchup_tween: Tween = null
var _fade_tween: Tween = null
var _hide_timer: float = 0.0
var _is_faded_out: bool = false
var _health_comp_ref: WeakRef = null

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 设置自身控件最小尺寸，便于容器排版
	custom_minimum_size = Vector2(bar_width + 2.0, bar_height + 2.0)
	size = custom_minimum_size

	if center_origin:
		position = Vector2(0.0, overhead_offset_y)

	_displayed_health = current_health
	_catchup_health = current_health

	if auto_hide and current_health >= max_health - 0.001:
		modulate.a = 0.0
		_is_faded_out = true
	else:
		modulate.a = 1.0
		_is_faded_out = false

	queue_redraw()

func _process(delta: float) -> void:
	# 自动隐退倒计时
	if auto_hide and not _is_faded_out:
		if current_health >= max_health - 0.001:
			_hide_timer -= delta
			if _hide_timer <= 0.0:
				_fade_out()
		else:
			# 未满血时也遵循受击后一段延时渐隐
			_hide_timer -= delta
			if _hide_timer <= 0.0:
				_fade_out()

## 绑定目标生命值组件，自动同步血量并监听信号
func setup(health_component: Node) -> void:
	if health_component == null:
		return

	_health_comp_ref = weakref(health_component)

	# 读取组件当前值
	if "max_health" in health_component:
		max_health = float(health_component.max_health)
	if "current_health" in health_component:
		current_health = float(health_component.current_health)

	_displayed_health = current_health
	_catchup_health = current_health

	# 信号安全连接
	if health_component.has_signal("health_changed") and not health_component.is_connected("health_changed", Callable(self, "_on_health_changed")):
		health_component.connect("health_changed", Callable(self, "_on_health_changed"))
	if health_component.has_signal("damaged") and not health_component.is_connected("damaged", Callable(self, "_on_damaged")):
		health_component.connect("damaged", Callable(self, "_on_damaged"))
	if health_component.has_signal("healed") and not health_component.is_connected("healed", Callable(self, "_on_healed")):
		health_component.connect("healed", Callable(self, "_on_healed"))
	if health_component.has_signal("died") and not health_component.is_connected("died", Callable(self, "_on_died")):
		health_component.connect("died", Callable(self, "_on_died"))

	if auto_hide and current_health >= max_health - 0.001:
		modulate.a = 0.0
		_is_faded_out = true
	else:
		modulate.a = 1.0
		_is_faded_out = false

	queue_redraw()

## 手动直接设置血量数值 (解耦通用)
func set_health(new_health: float, new_max_health: float = -1.0, animate: bool = true) -> void:
	if new_max_health > 0.0:
		max_health = new_max_health

	var prev_health := current_health
	current_health = clampf(new_health, 0.0, max_health)

	_wake_and_reset_timer()

	if not animate:
		_displayed_health = current_health
		_catchup_health = current_health
		if _catchup_tween:
			_catchup_tween.kill()
		queue_redraw()
		return

	if current_health < prev_health:
		# 扣血受击：前景血条立刻扣减，黄色残影条短暂停顿后平滑追赶
		_displayed_health = current_health
		if show_damage_catchup:
			if _catchup_tween:
				_catchup_tween.kill()
			_catchup_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_catchup_tween.tween_interval(catchup_delay)
			_catchup_tween.tween_method(Callable(self, "_set_catchup_health"), _catchup_health, current_health, catchup_duration)
		else:
			_catchup_health = current_health
	else:
		# 回血治愈：血条平滑上涨，残影条同步跟进
		if _catchup_tween:
			_catchup_tween.kill()
		_catchup_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_catchup_tween.tween_method(Callable(self, "_set_displayed_health"), _displayed_health, current_health, 0.25)
		_catchup_health = current_health

	queue_redraw()

func _set_displayed_health(val: float) -> void:
	_displayed_health = val
	queue_redraw()

func _set_catchup_health(val: float) -> void:
	_catchup_health = val
	queue_redraw()

func _on_health_changed(new_h: float, max_h: float) -> void:
	set_health(new_h, max_h, true)

func _on_damaged(_amount: float, _source: Node) -> void:
	_wake_and_reset_timer()

func _on_healed(_amount: float, _source: Node) -> void:
	_wake_and_reset_timer()

func _on_died() -> void:
	_fade_out()

func _wake_and_reset_timer() -> void:
	_hide_timer = auto_hide_delay
	if _is_faded_out:
		_fade_in()

func _fade_in() -> void:
	_is_faded_out = false
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fade_tween.tween_property(self, "modulate:a", 1.0, fade_duration * 0.5)

func _fade_out() -> void:
	_is_faded_out = true
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fade_tween.tween_property(self, "modulate:a", 0.0, fade_duration)

func _draw() -> void:
	if max_health <= 0.001:
		return

	var w := bar_width
	var h := bar_height

	var ox: float = -roundf(w * 0.5) if center_origin else 0.0
	var oy: float = -roundf(h * 0.5) if center_origin else 0.0

	# 1. 1px 黑色硬质像素外边框
	if show_border:
		draw_rect(Rect2(ox - 1.0, oy - 1.0, w + 2.0, h + 2.0), border_color, false, 1.0)

	# 2. 血槽底色 (深色底)
	draw_rect(Rect2(ox, oy, w, h), bg_color, true)

	var hp_ratio := clampf(_displayed_health / max_health, 0.0, 1.0)
	var catchup_ratio := clampf(_catchup_health / max_health, 0.0, 1.0)

	var fill_w: float = roundf(w * hp_ratio)
	var catchup_w: float = roundf(w * catchup_ratio)

	# 3. 延迟缓冲黄色残影条 (画在底槽上、血条下)
	if show_damage_catchup and catchup_w > fill_w:
		draw_rect(Rect2(ox + fill_w, oy, catchup_w - fill_w, h), catchup_color, true)

	# 4. 前景生命值条
	if fill_w > 0.0:
		var fill_col := health_color
		if dynamic_color:
			if hp_ratio > 0.5:
				fill_col = health_color
			elif hp_ratio > 0.2:
				fill_col = warning_color
			else:
				fill_col = critical_color

		draw_rect(Rect2(ox, oy, fill_w, h), fill_col, true)

		# 5. 顶部 1 像素高光微提亮 (增强像素立体感，高度 >= 3 时绘制)
		if h >= 3.0:
			var highlight_col := Color(1.0, 1.0, 1.0, 0.35)
			draw_line(Vector2(ox, oy), Vector2(ox + fill_w - 1.0, oy), highlight_col, 1.0)
