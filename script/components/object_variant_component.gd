# object_variant_component.gd —— 物体多形态与视觉变种组件 (支持树木双层结构与石头等单精灵物体)
class_name ObjectVariantComponent
extends Node

@export_group("双层树木变体池 (Canopy + Trunk)")
## 是否开启成对匹配（true: 树干与树冠按相同序号成对抽取；false: 随机自由组合）
@export var pair_mode: bool = true
## 树冠 (Canopy) 备选贴图列表
@export var canopy_variants: Array[Texture2D] = []
## 树干 (Trunk) 备选贴图列表
@export var trunk_variants: Array[Texture2D] = []
## 针对不同变种树冠的 Y 轴相对高度微调 (可选，如留空则维持默认 -60)
@export var canopy_y_offsets: Array[float] = []

@export_group("单精灵物体变体池 (石头/灌木/道具)")
## 目标单精灵节点名称 (默认 "Sprite2D")
@export var single_sprite_node_name: String = "Sprite2D"
## 单精灵贴图备选列表 (用于石头、箱子等物体)
@export var single_sprite_variants: Array[Texture2D] = []

@export_group("视口多节点变种模式 (Visuals 容器)")
## 变种容器节点名称 (默认 "Visuals")。如果场景树中存在此节点，将自动优先采用多节点视口模式！
@export var visuals_container_name: String = "Visuals"

@export_group("零成本多样性倍增 (镜像与微缩放)")
## 是否允许随机左右镜像翻转 (左右对称自然树木/石头，直接使变种表现翻倍)
@export var allow_flip_h: bool = true
## 尺寸随机微调区间 (例如 (0.96, 1.04) 可使树木呈现细微高矮胖瘦差异；(1.0, 1.0) 为不缩放)
@export var scale_range: Vector2 = Vector2(0.96, 1.04)

var parent_object: Node2D = null

func _ready() -> void:
	# 向上查找实体根节点
	var curr := get_parent()
	while curr:
		if curr is Node2D:
			parent_object = curr as Node2D
			break
		curr = curr.get_parent()

	if parent_object == null:
		return

	_apply_variant()

# 应用随机变种
func _apply_variant() -> void:
	# === 模式一：优先检查场景中是否存在多节点变种容器 (Visuals 模式) ===
	var visuals_node := parent_object.find_child(visuals_container_name, true, false) as Node2D
	if visuals_node and visuals_node.get_child_count() > 0:
		var variant_children: Array[Node] = visuals_node.get_children()
		var chosen_idx := randi() % variant_children.size()
		var chosen_variant: Node2D = null

		for i in range(variant_children.size()):
			var v := variant_children[i] as Node2D
			if v == null:
				continue
			if i == chosen_idx:
				chosen_variant = v
				v.visible = true
			else:
				# 移出并销毁未选中的多余变种，确保场景树纯净、性能最佳
				visuals_node.remove_child(v)
				v.queue_free()

		if chosen_variant:
			# 水平镜像翻转 (整个 Variant 作为一个整体翻转，树干与树冠相对锚点绝对精准！)
			if allow_flip_h and randf() > 0.5:
				chosen_variant.scale.x = -absf(chosen_variant.scale.x)

			# 极轻微尺寸扰动
			if scale_range.x > 0.01 and scale_range.y > 0.01:
				if not is_equal_approx(scale_range.x, 1.0) or not is_equal_approx(scale_range.y, 1.0):
					var s := randf_range(scale_range.x, scale_range.y)
					chosen_variant.scale *= s

		return

	# === 模式二：旧版贴图数组替换模式 (回退兜底) ===
	var canopy_node := parent_object.find_child("Canopy", true, false) as Sprite2D
	var trunk_node := parent_object.find_child("Trunk", true, false) as Sprite2D
	var single_sprite_node := parent_object.find_child(single_sprite_node_name, true, false) as Sprite2D

	# 1. 树木双层模式处理
	if canopy_node or trunk_node:
		var canopy_count := canopy_variants.size()
		var trunk_count := trunk_variants.size()

		if canopy_count > 0 or trunk_count > 0:
			var canopy_idx := 0
			var trunk_idx := 0

			if pair_mode and canopy_count > 0 and trunk_count > 0:
				var min_count := mini(canopy_count, trunk_count)
				var rand_idx := randi() % min_count
				canopy_idx = rand_idx
				trunk_idx = rand_idx
			else:
				if canopy_count > 0:
					canopy_idx = randi() % canopy_count
				if trunk_count > 0:
					trunk_idx = randi() % trunk_count

			# 替换树冠贴图
			if canopy_node and canopy_idx < canopy_count and canopy_variants[canopy_idx] != null:
				canopy_node.texture = canopy_variants[canopy_idx]
				# 应用专属树冠 Y 轴偏移 (如果有配置)
				if canopy_idx < canopy_y_offsets.size():
					canopy_node.position.y = canopy_y_offsets[canopy_idx]

			# 替换树干贴图
			if trunk_node and trunk_idx < trunk_count and trunk_variants[trunk_idx] != null:
				trunk_node.texture = trunk_variants[trunk_idx]

		# 左右镜像翻转
		if allow_flip_h and randf() > 0.5:
			if canopy_node:
				canopy_node.flip_h = true
			if trunk_node:
				trunk_node.flip_h = true

	# 2. 单精灵物体模式处理 (如石头、箱子)
	elif single_sprite_node and single_sprite_variants.size() > 0:
		var s_idx := randi() % single_sprite_variants.size()
		if single_sprite_variants[s_idx] != null:
			single_sprite_node.texture = single_sprite_variants[s_idx]

		if allow_flip_h and randf() > 0.5:
			single_sprite_node.flip_h = true

	# 3. 极细微缩放扰动 (高矮胖瘦自然差异)
	if scale_range.x > 0.01 and scale_range.y > 0.01:
		if not is_equal_approx(scale_range.x, 1.0) or not is_equal_approx(scale_range.y, 1.0):
			var s := randf_range(scale_range.x, scale_range.y)
			# 保留父级原有的正负符号 (如果父级本身有翻转)
			var sign_x := signf(parent_object.scale.x) if parent_object.scale.x != 0.0 else 1.0
			parent_object.scale = Vector2(s * sign_x, s)

