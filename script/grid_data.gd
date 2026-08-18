# ============================================================
# grid_date.gd —— 全局高度场数据（Autoload 单例）
#
# 【当前功能】只有一件：遍历所有 TileMapLayer，
#            把每层有砖的格子存进三维字典 grid 里。
#
# 【注释标记】
#   [自定义] = 我们自己写的
#   [官方API] = Godot 自带的方法/属性
# ============================================================


extends Node


# [自定义] 每层楼之间的视觉高度差（像素）。
# 等距瓷砖有 8px 视觉厚度，所以高一层 = Y 更小 = 负方向偏移。
# 将来做楼层换算/翻越/排序时统一用这个常量。
const FLOOR_HEIGHT: float = 8.0


# [自定义] 高度场核心数组。
# 用 Dictionary 模拟"三维布尔数组"：
#   key   = Vector3i(x, y, z)  格子坐标 + 楼层
#   value = true               该格该层有砖
#
# 例：grid[Vector3i(5, 3, 0)] = true
#     → 格子(5,3) 在地面层（z=0）有砖
var grid: Dictionary = {}


# [自定义] 各楼层 TileMapLayer 引用，从低到高排列。
#   layers[0] = layer0（地面）
#   layers[1] = layer1（高一层）
#   layers[2] = layer2（高两层）
# 构建时用它遍历；将来查询时也要用它知道总层数。
var layers: Array[TileMapLayer] = []


# [自定义] 遍历所有 TileMapLayer，生成 grid。
# 参数 layer_nodes：按"从低到高"顺序传各个层节点。
#
# 使用（放在主场景 _ready 里）：
#   GridData.build_from_layers([$layer0, $layer1, $layer2])
func build_from_layers(layer_nodes: Array[TileMapLayer]) -> void:
	layers = layer_nodes
	grid.clear()  # [官方API] Dictionary.clear() 清空旧数据

	# 从低到高遍历每一层
	for z in layers.size():
		# [官方API] TileMapLayer.get_used_cells()
		# 返回这层里所有"有砖"的格子坐标数组
		var cells: Array[Vector2i] = layers[z].get_used_cells()

		# 把这层每个有砖的格子记进 grid
		for cell in cells:
			grid[Vector3i(cell.x, cell.y, z)] = true


# [自定义] 世界坐标（平面）→ 格子坐标
# 用最低层换算，因为所有层的格子坐标系统一（position 偏移不影响格子编号）
func world_to_cell(world_pos: Vector2) -> Vector2i:
	if layers.is_empty():
		return Vector2i.ZERO
	return layers[0].local_to_map(layers[0].to_local(world_pos))


# [自定义] 查询某格最高的有砖楼层（玩家脚下的平台层）
func get_highest_floor(cell: Vector2i) -> int:
	for z in range(layers.size() - 1, -1, -1):
		if grid.has(Vector3i(cell.x, cell.y, z)):
			return z
	return 0


# [自定义] 楼层号 → Y 像素偏移（0→-8，1→-16，2→-24...，永远≤0）
# 说明：为什么每层都要多减一个 FLOOR_HEIGHT？
#   1. 等距瓷砖的渲染纹理原点默认在顶面，但地图把纹理原点下移了 8px，
#      使 tile 贴到格子上显得正确 → 角色站在任何一层(含0层地面)都要额外上移 8px。
#   2. 再叠加楼层高度：0层+0、1层+8、2层+16。
#   因此总偏移 = -(floor × 8 + 8) = -(floor + 1) × 8
func get_floor_pixel_offset(floor: int) -> float:
	return -float(floor + 1) * FLOOR_HEIGHT
