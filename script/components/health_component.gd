# health_component.gd —— 通用模块化生物生命值组件 (支持受击伤害结算、变红反馈与死亡行为)
class_name HealthComponent
extends Node

signal health_changed(new_health: float, max_health: float)
signal damaged(amount: float, source: Node)
signal healed(amount: float, source: Node)
signal died()

@export_group("生命值基础属性 (Health Attributes)")
## 最大生命值 (可在检查器针对各类生物个性化配置)
@export var max_health: float = 100.0:
	set(val):
		max_health = maxf(val, 1.0)
		if is_inside_tree():
			health_changed.emit(current_health, max_health)

## 当前生命值
@export var current_health: float = 100.0:
	set(val):
		current_health = clampf(val, 0.0, max_health)
		if is_inside_tree():
			health_changed.emit(current_health, max_health)

## 无敌状态开关 (调试、Boss霸体或特殊保护机制)
@export var is_invulnerable: bool = false

@export_group("受击视觉表现 (Hit Feedback)")
## 是否启用受击瞬间变红高亮闪烁
@export var enable_hit_flash: bool = true
## 受击变色闪烁目标颜色 (默认浅鲜红)
@export var hit_flash_color: Color = Color(1.0, 0.35, 0.35, 1.0)
## 受击闪烁恢复时长 (秒)
@export var hit_flash_duration: float = 0.12

@export_group("死亡行为 (Death Behavior)")
## 生命耗尽归零时是否自动销毁实体
@export var destroy_on_death: bool = true
## 死亡销毁延迟时间 (秒，用于播放受击音效或残存效果)
@export var death_delay: float = 0.08

var entity: Node2D = null
var _sprite: CanvasItem = null
var _flash_tween: Tween = null
var _is_dead: bool = false

func _ready() -> void:
	_ensure_init()
	# 确保初次载入时血量合法
	current_health = clampf(current_health, 0.0, max_health)
	_is_dead = (current_health <= 0.001)

func _ensure_init() -> void:
	if entity == null:
		# 1. 向上遍历检索挂载的宿主实体 (支持放置在 LogicScript 等逻辑容器内)
		var curr := get_parent()
		while curr:
			if curr is Node2D:
				entity = curr as Node2D
				break
			curr = curr.get_parent()

		if entity:
			# 检索实体的贴图渲染节点
			_sprite = entity.find_child("AnimatedSprite2D", true, false) as CanvasItem
			if _sprite == null:
				_sprite = entity.find_child("Sprite2D", true, false) as CanvasItem

			# 2. 自动检索同宿主下的 HealthBar UI 并自动完成绑定对接
			var bar: Node = entity.find_child("HealthBar", true, false)
			if bar and bar.has_method("setup"):
				bar.call("setup", self)

## 受到伤害核心入口：处理免伤、血量扣减、受击红闪打击感与死亡判定
func take_damage(amount: float, source: Node = null) -> void:
	_ensure_init()
	if _is_dead or is_invulnerable or amount <= 0.0:
		return

	current_health = maxf(current_health - amount, 0.0)

	damaged.emit(amount, source)
	health_changed.emit(current_health, max_health)

	# 受击红闪打击感反馈
	if enable_hit_flash and _sprite and is_instance_valid(_sprite):
		if _flash_tween:
			_flash_tween.kill()
		_sprite.modulate = hit_flash_color
		_flash_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_flash_tween.tween_property(_sprite, "modulate", Color.WHITE, hit_flash_duration)

	# 濒死与死亡处理
	if current_health <= 0.001:
		_trigger_death()

## 治愈恢复生命值
func heal(amount: float, source: Node = null) -> void:
	_ensure_init()
	if _is_dead or amount <= 0.0:
		return

	var old_h := current_health
	current_health = minf(current_health + amount, max_health)
	var real_healed := current_health - old_h

	if real_healed > 0.0:
		healed.emit(real_healed, source)
		health_changed.emit(current_health, max_health)

## 当前生物是否存活
func is_alive() -> bool:
	return not _is_dead and current_health > 0.001

## 获取当前生命值百分比 (0.0 ~ 1.0)
func get_health_ratio() -> float:
	return clampf(current_health / maxf(max_health, 0.001), 0.0, 1.0)

## 内部触发死亡逻辑
func _trigger_death() -> void:
	if _is_dead:
		return
	_is_dead = true
	died.emit()

	if destroy_on_death and entity and is_instance_valid(entity):
		# 死亡瞬间立即禁用物理碰撞与AI，防止鞭尸与幽灵碰撞
		if entity is CollisionObject2D:
			(entity as CollisionObject2D).collision_layer = 0
			(entity as CollisionObject2D).collision_mask = 0

		# 暂停生物 AI 思考
		var ai: Node = entity.find_child("WanderAIComponent", true, false)
		if ai and "enable_wander" in ai:
			ai.enable_wander = false

		if death_delay > 0.001 and is_inside_tree():
			var tree := get_tree()
			if tree:
				await tree.create_timer(death_delay).timeout
		if is_instance_valid(entity):
			entity.queue_free()
