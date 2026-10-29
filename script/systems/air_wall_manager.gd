# air_wall_manager.gd —— 2D 纯平面地图边界虚空空气墙自动生成器
class_name AirWallManager
extends StaticBody2D

const DIAMOND_POINTS: PackedVector2Array = [
	Vector2(0, -16),
	Vector2(32, 0),
	Vector2(0, 16),
	Vector2(-32, 0)
]

@export var ground_layer: TileMapLayer
@export var wall_thickness_rings: int = 2 # 边缘空气墙缓冲环数 (默认 2 层防穿透)

func _ready() -> void:
	# 空气墙属于物理层 2 ("空气墙")，不监听其他物体 (mask = 0)
	collision_layer = 2
	collision_mask = 0
	add_to_group("air_walls")
	
	# 延后一帧以确保所有图层加载完毕
	call_deferred("rebuild_walls")

## 重新扫描基层 TileMapLayer 并生成虚空格边界碰撞体
func rebuild_walls() -> void:
	# 1. 清理已有子碰撞体
	for child in get_children():
		child.queue_free()

	var target_layer := ground_layer
	if target_layer == null:
		target_layer = GridData.ground_layer
	if target_layer == null:
		return

	var used_cells := target_layer.get_used_cells()
	if used_cells.is_empty():
		return

	# 2. 收集所有有效瓦片大格集合
	var used_set: Dictionary = {}
	for c in used_cells:
		used_set[c] = true

	# 3. 收集环绕在陆地边缘的虚空格 (Ring 1)
	var all_void_cells: Dictionary = {}
	var current_frontier: Dictionary = {}

	for c: Vector2i in used_cells:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var nc := c + Vector2i(dx, dy)
				if not used_set.has(nc):
					all_void_cells[nc] = true
					current_frontier[nc] = true

	# 4. 根据设定的厚度向外扩展缓冲环 (Ring 2+)
	for _r in range(1, wall_thickness_rings):
		var next_frontier: Dictionary = {}
		for key in current_frontier.keys():
			var c: Vector2i = key
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var nc := c + Vector2i(dx, dy)
					if not used_set.has(nc) and not all_void_cells.has(nc):
						all_void_cells[nc] = true
						next_frontier[nc] = true
		current_frontier = next_frontier

	# 5. 在每个虚空格位置实例化 64x32 菱形碰撞体
	for key in all_void_cells.keys():
		var void_cell: Vector2i = key
		var col := CollisionPolygon2D.new()
		col.position = GridData.cell_to_world(void_cell)
		col.polygon = DIAMOND_POINTS
		add_child(col)
