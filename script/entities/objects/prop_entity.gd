# prop_entity.gd —— 通用单图层物体/作物/道具实体基类 (支持多变体随机与切换、专属对齐微调)
@tool
class_name PropEntity
extends Node2D

@export_group("贴图变体配置")
## 物体贴图变体列表
@export var texture_variants: Array[Texture2D] = []

## 各变体专属对齐偏移 (在编辑器中修改可实时预览)
@export var variant_offsets: Array[Vector2] = []:
	set(v):
		variant_offsets = v
		_apply_variant(current_variant)

@export_group("实时预览与调试")
## 当前选中的变体索引
@export var current_variant: int = 0:
	set(v):
		current_variant = v
		_apply_variant(current_variant)

@onready var sprite: Sprite2D = $Sprite2D if has_node("Sprite2D") else null

func _ready() -> void:
	if has_meta("variant"):
		set_variant(int(get_meta("variant")))
	elif not Engine.is_editor_hint():
		randomize_variant()
	else:
		_apply_variant(current_variant)

func get_variant_count() -> int:
	return texture_variants.size()

func get_variant() -> int:
	return current_variant

func randomize_variant() -> int:
	var count := get_variant_count()
	if count <= 0:
		return 0
	var chosen := randi() % count
	set_variant(chosen)
	return chosen

func set_variant(idx: int) -> void:
	var count := get_variant_count()
	if count <= 0:
		return
	idx = clampi(idx, 0, count - 1)
	current_variant = idx
	set_meta("variant", idx)
	_apply_variant(idx)

func _get_sprite() -> Sprite2D:
	if sprite and is_instance_valid(sprite):
		return sprite
	return get_node_or_null("Sprite2D") as Sprite2D

func _apply_variant(idx: int) -> void:
	var s := _get_sprite()
	if s and idx >= 0 and idx < texture_variants.size():
		if texture_variants[idx]:
			s.texture = texture_variants[idx]
	if s and idx >= 0 and idx < variant_offsets.size():
		s.offset = variant_offsets[idx]
