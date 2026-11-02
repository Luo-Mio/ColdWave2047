# tree_entity.gd —— 树木实体通用基类 (支持多变体动态切换、独立树根对齐微调、X-Ray 透视、编辑器实时预览)
@tool
class_name TreeEntity
extends StaticBody2D

@export_group("贴图变体配置")
## 树冠贴图变体列表 (与 trunk_variants 一一对应)
@export var canopy_variants: Array[Texture2D] = []

## 树干贴图变体列表 (与 canopy_variants 一一对应)
@export var trunk_variants: Array[Texture2D] = []

## 各变体专属树根对齐偏移 (用于微调不同形态的树根精准落在 (0, 0) 地面中心，在编辑器中修改可实时预览)
@export var variant_offsets: Array[Vector2] = []:
	set(v):
		variant_offsets = v
		_apply_variant(current_variant)

@export_group("实时预览与调试")
## 当前选中的变体索引 (在编辑器修改可实时在 2D 视口内预览形态与树根对齐位置)
@export var current_variant: int = 0:
	set(v):
		current_variant = v
		_apply_variant(current_variant)

## 一键自动推算并填充全部变体的树根居中偏移 (点击勾选即可自动计算)
@export var auto_align_roots_trigger: bool = false:
	set(v):
		if v:
			auto_calculate_offsets()
			auto_align_roots_trigger = false

@onready var trunk_sprite: Sprite2D = $Visuals/Trunk if has_node("Visuals/Trunk") else null
@onready var canopy_sprite: Sprite2D = $Visuals/Canopy if has_node("Visuals/Canopy") else null

func _ready() -> void:
	if has_meta("variant"):
		set_variant(int(get_meta("variant")))
	elif not Engine.is_editor_hint():
		# 运行时且未指定特定变体时，自动随机选取一个可用变体
		randomize_variant()
	else:
		_apply_variant(current_variant)

## 获取可用变体总数
func get_variant_count() -> int:
	return max(canopy_variants.size(), trunk_variants.size())

## 获取当前变体索引
func get_variant() -> int:
	return current_variant

## 随机选取一个变体并应用，返回选中的索引
func randomize_variant() -> int:
	var count := get_variant_count()
	if count <= 0:
		return 0
	var chosen := randi() % count
	set_variant(chosen)
	return chosen

## 设置指定变体索引
func set_variant(idx: int) -> void:
	var count := get_variant_count()
	if count <= 0:
		return
	idx = clampi(idx, 0, count - 1)
	current_variant = idx
	set_meta("variant", idx)
	_apply_variant(idx)

## 安全获取 Trunk 节点 (兼容 @tool 编辑器即时预览)
func _get_trunk_sprite() -> Sprite2D:
	if trunk_sprite and is_instance_valid(trunk_sprite):
		return trunk_sprite
	return get_node_or_null("Visuals/Trunk") as Sprite2D

## 安全获取 Canopy 节点 (兼容 @tool 编辑器即时预览)
func _get_canopy_sprite() -> Sprite2D:
	if canopy_sprite and is_instance_valid(canopy_sprite):
		return canopy_sprite
	return get_node_or_null("Visuals/Canopy") as Sprite2D

## 内部执行变体贴图与专属对齐偏移应用
func _apply_variant(idx: int) -> void:
	var trunk := _get_trunk_sprite()
	var canopy := _get_canopy_sprite()

	if idx >= 0 and idx < canopy_variants.size() and canopy:
		if canopy_variants[idx]:
			canopy.texture = canopy_variants[idx]

	if idx >= 0 and idx < trunk_variants.size() and trunk:
		if trunk_variants[idx]:
			trunk.texture = trunk_variants[idx]

	# 应用该变体专属的树根对齐偏移量
	if idx >= 0 and idx < variant_offsets.size():
		var off: Vector2 = variant_offsets[idx]
		if canopy:
			canopy.offset = off
		if trunk:
			trunk.offset = off

## 自动扫描树干底边像素并推算各变体理论对齐偏移量
func auto_calculate_offsets() -> void:
	var new_offsets: Array[Vector2] = []
	for trunk_tex in trunk_variants:
		if trunk_tex:
			var img: Image = trunk_tex.get_image()
			if img:
				var rect: Rect2i = img.get_used_rect()
				var bottom_y: int = rect.end.y - 1
				var min_x: int = rect.end.x
				var max_x: int = rect.position.x
				for y in range(bottom_y, max(rect.position.y, bottom_y - 3), -1):
					for x in range(rect.position.x, rect.end.x):
						if img.get_pixel(x, y).a > 0.1:
							min_x = mini(min_x, x)
							max_x = maxi(max_x, x)
					if max_x >= min_x:
						break
				var center_x: float = (float(min_x + max_x)) / 2.0 if max_x >= min_x else float(rect.position.x + rect.size.x / 2.0)
				var half_w: float = float(img.get_width()) / 2.0
				var half_h: float = float(img.get_height()) / 2.0
				# 稍作下沉 (+2px) 让树根稳重地扎入地面网格中心菱形
				var calc_x: float = round(half_w - center_x)
				var calc_y: float = round(half_h - float(bottom_y)) + 2.0
				new_offsets.append(Vector2(calc_x, calc_y))
				continue
		new_offsets.append(Vector2(0, -58))

	variant_offsets = new_offsets
	print("[TreeEntity] 已为 %d 个变体自动推算最佳对齐偏移: %s" % [variant_offsets.size(), variant_offsets])
	_apply_variant(current_variant)
