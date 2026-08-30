# drop_item.gd —— 自由实体（地面静止土堆 + 抛物线爆落物理）
class_name DropItem
extends Node2D

@export var item_id: String = "dirt"
@export var floor_level: int = 0
@export var base_position: Vector2 = Vector2.ZERO

# ==================== 可在检查器微调的抛物线物理参数 ====================
@export_group("抛物线抛射手感参数")
@export var arc_height: float = 10.0       # 抛物线最高拱起高度（数值越大飞得越高）
@export var fly_duration: float = 0.5     # 飞行总时间（秒，数值越小飞得越快越干脆）
@export var bounce_height: float = 4.0     # 落地二次微弱弹跳高度（设为 0 则直接落定不弹）
@export var bounce_duration: float = 0.12  # 二次弹跳时间（秒）
var _visual_sprite: Sprite2D
# ====================================================================

var layer_no: int = 999
var sort_key: float = 0.0
var foot_y: float = 0.0

# 掉落物贴图字典（未来加新掉落物直接在这里加一行）
const ITEM_TEXTURES: Dictionary = {
	"dirt": preload("res://resources/object/dirt.png"),
	"wheat": preload("res://resources/Plant/wheat/wheat.png"),
}

func _ready() -> void:
	add_to_group("drop_items")
	_visual_sprite = get_node_or_null("Sprite2D")
	_update_texture()
	_update_sorting()

# 保持 2.5D 深度排序准确
func _update_sorting() -> void:
	var landing_y := base_position.y + GridData.get_floor_pixel_offset(floor_level)
	foot_y = landing_y
	sort_key = GridData.cell_to_sort_key(GridData.world_to_cell(base_position))

	var parent_sort := get_parent()
	if parent_sort and parent_sort.has_method("insert_sort"):
		parent_sort.call("insert_sort", self)

# 【核心抛物线物理】：平滑从敲碎处飞溅到目标地面
func spawn_bounce(from_world_pos: Vector2, to_world_pos: Vector2, to_floor: int) -> void:
	base_position = to_world_pos
	floor_level = to_floor
	_update_sorting()

	var landing_pos := to_world_pos + Vector2(0.0, GridData.get_floor_pixel_offset(to_floor))
	global_position = from_world_pos

	var tween := create_tween().set_parallel(true)
	# 1. 水平飞行
	tween.tween_property(self, "global_position:x", landing_pos.x, fly_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# 2. 垂直抛物线（先冲顶后落定）
	var peak_y := minf(from_world_pos.y, landing_pos.y) - arc_height
	var half_time := fly_duration * 0.5
	var y_tween := create_tween()
	y_tween.tween_property(self, "global_position:y", peak_y, half_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	y_tween.tween_property(self, "global_position:y", landing_pos.y, half_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	# 3. 落地轻微弹跳（可选）
	if bounce_height > 0.0:
		var half_bounce := bounce_duration * 0.5
		y_tween.tween_property(self, "global_position:y", landing_pos.y - bounce_height, half_bounce).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		y_tween.tween_property(self, "global_position:y", landing_pos.y, half_bounce).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

# 动态切换掉落物类型（自动更换贴图）
func set_item_type(new_id: String) -> void:
	item_id = new_id
	_update_texture()
func _update_texture() -> void:
	if _visual_sprite and ITEM_TEXTURES.has(item_id):
		_visual_sprite.texture = ITEM_TEXTURES[item_id]