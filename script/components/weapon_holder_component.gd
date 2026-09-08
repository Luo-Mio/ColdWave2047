# weapon_holder_component.gd —— 手持武器与 360° 旋转瞄准组件 (支持主角与人形怪物)
class_name WeaponHolderComponent
extends Node

@export_group("手持武器系统配置")
## 是否自动同步主角底部快捷栏选中的物品。主角设为 true，NPC或怪物设为 false（由代码手动分配武器）
@export var enable_hotbar_sync: bool = true

var is_weapon_active: bool = false
var current_aim_dir: Vector2 = Vector2.DOWN

var entity: Node2D
var hand_node: Node2D
var weapon_sprite: Sprite2D
var animated_sprite: AnimatedSprite2D

func _ready() -> void:
	# 向上查找实体根节点 (支持组件放置在 LogicScript 容器内)
	var curr := get_parent()
	while curr:
		if curr is Node2D:
			entity = curr as Node2D
			break
		curr = curr.get_parent()

	if entity == null:
		return

	# 查找关联的视觉节点
	hand_node = entity.find_child("hand", true, false) as Node2D
	if hand_node:
		weapon_sprite = hand_node.find_child("Sprite2D", true, false) as Sprite2D
	animated_sprite = entity.find_child("AnimatedSprite2D", true, false) as AnimatedSprite2D

var _last_slot_index: int = -999

func _process(_delta: float) -> void:
	if entity == null:
		return

	# 1. 如果启用了快捷栏监听 (玩家模式)
	if enable_hotbar_sync:
		_check_hotbar()

	# 2. 武器显示与 360° 旋转瞄准逻辑
	if is_weapon_active:
		if hand_node:
			hand_node.visible = true

		# 计算武器朝向：优先使用 AimController 的 3D 屏幕投影朝向 (与激光虚线 100% 对齐)
		var aim_ctrl: Node = entity.find_child("AimController", true, false) if entity else null
		if aim_ctrl and aim_ctrl.get("is_aim_active") and aim_ctrl.has_method("get_screen_aim_direction"):
			current_aim_dir = aim_ctrl.call("get_screen_aim_direction")
		else:
			var chest_pos := animated_sprite.global_position if animated_sprite else entity.global_position
			var mouse_pos := entity.get_global_mouse_position()
			var delta_pos := mouse_pos - chest_pos
			if delta_pos.length_squared() > 1.0:
				current_aim_dir = delta_pos.normalized()

		# 驱动手部法杖旋转跟随鼠标
		if hand_node and weapon_sprite:
			hand_node.rotation = current_aim_dir.angle()

			# 向左瞄准时垂直翻转贴图，防止木棍上下倒立
			var angle_rad := current_aim_dir.angle()
			weapon_sprite.flip_v = (absf(angle_rad) > PI * 0.5)

			# 朝北（上方）瞄准时把武器放到背后，朝南（下方）瞄准时放在身前
			hand_node.show_behind_parent = (current_aim_dir.y < 0.0)
	else:
		if hand_node:
			hand_node.visible = false
		current_aim_dir = Vector2.ZERO

# 检查当前底部物品栏是否处于手持武器或瞄准道具状态 (仅在槽位发生变动时触发)
func _check_hotbar() -> void:
	var hotbar: Node = get_tree().root.find_child("hotbar", true, false)
	var aim_ctrl: Node = entity.find_child("AimController", true, false) if entity else null
	if hotbar and hotbar.has_method("get_active_item"):
		var cur_index: int = hotbar.get("active_index") if ("active_index" in hotbar) else -1
		if cur_index == _last_slot_index:
			return
		_last_slot_index = cur_index

		var active_item: Dictionary = hotbar.call("get_active_item")
		var has_aim_config: bool = active_item.has("aim_config")
		var is_weapon: bool = (active_item.get("type") == 2) # 兼容原 WEAPON 枚举
		var should_aim: bool = has_aim_config or is_weapon
		
		is_weapon_active = should_aim
		if is_weapon_active:
			# 同步武器/手持道具贴图
			if active_item.has("weapon_tex") and weapon_sprite:
				if weapon_sprite.texture == null or weapon_sprite.texture.resource_path != active_item["weapon_tex"]:
					weapon_sprite.texture = load(active_item["weapon_tex"])
			elif weapon_sprite and not active_item.has("weapon_tex"):
				weapon_sprite.texture = null

			# 将道具的瞄准配置注入 AimController
			if aim_ctrl:
				if has_aim_config and active_item["aim_config"] is Dictionary:
					aim_ctrl.apply_aim_config(active_item["aim_config"])
				else:
					aim_ctrl.is_aim_active = true
		else:
			if aim_ctrl and aim_ctrl.get("is_aim_active"):
				aim_ctrl.clear_aim_config()
	else:
		_last_slot_index = -999
		is_weapon_active = false
		if aim_ctrl and aim_ctrl.get("is_aim_active"):
			aim_ctrl.clear_aim_config()

# 供外部 (如怪物/NPC或掉落装备系统) 手动指定武器贴图
func set_weapon(weapon_tex_path: String) -> void:
	if weapon_sprite:
		weapon_sprite.texture = load(weapon_tex_path)
	is_weapon_active = true
	if hand_node:
		hand_node.visible = true

# 收起武器
func clear_weapon() -> void:
	is_weapon_active = false
	if hand_node:
		hand_node.visible = false

# 兼容旧接口
func update_held_item(item_data: Dictionary) -> void:
	if item_data.is_empty() or item_data.get("type") != 2:
		clear_weapon()
	else:
		if item_data.has("weapon_tex"):
			set_weapon(item_data["weapon_tex"])

