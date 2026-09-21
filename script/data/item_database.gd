# item_database.gd —— 全局物品注册库与测试数据中心
class_name ItemDatabase
extends RefCounted

enum Category {
	ALL,
	TREE,
	PLANT,
	TILE,
	WEAPON,
	OBJECT,
}

enum ItemType {
	TILE = 0,
	OBJECT = 1,
	WEAPON = 2,
}

# 分类显示名称映射
const CATEGORY_NAMES: Dictionary = {
	Category.ALL: "全部",
	Category.TREE: "🌲 树木",
	Category.PLANT: "🌾 植被",
	Category.TILE: "🧱 地砖",
	Category.WEAPON: "⚔️ 武器",
	Category.OBJECT: "📦 物品",
}

# 全局物品总表
static var ITEMS: Array[Dictionary] = [
	# --- 树木 (TREE) ---
	{
		"id": "oak_tree",
		"name": "橡树",
		"category": Category.TREE,
		"type": ItemType.OBJECT,
		"scene": "res://scene/object/tree/OakTree.tscn",
		"icon": "res://resources/tree/OakTree/AutumnTree.png",
		"grid_size": Vector2i(4, 4),
		"description": "茂密的秋季橡树，占地 4x4 格，树冠支持透视遮挡。"
	},
	{
		"id": "birch_tree",
		"name": "白桦树",
		"category": Category.TREE,
		"type": ItemType.OBJECT,
		"scene": "res://scene/object/tree/birch_tree.tscn",
		"icon": "res://resources/tree/BirchTree/BirchTree.png",
		"grid_size": Vector2i(4, 4),
		"description": "优雅挺拔的白桦树，白色树干，金黄秋叶，占地 4x4 格。"
	},

	# --- 植被与农作物 (PLANT) ---
	{
		"id": "wheat",
		"name": "小麦",
		"category": Category.PLANT,
		"type": ItemType.OBJECT,
		"scene": "res://scene/object/wheat.tscn",
		"icon": "res://resources/Plant/wheat/wheat.png",
		"grid_size": Vector2i(1, 1),
		"description": "1x1 微格精细种植农作物，随地砖破坏连带瓦解。"
	},

	# --- 建筑地砖 (TILE) ---
	{
		"id": "dirt_tile",
		"name": "新泥土砖",
		"category": Category.TILE,
		"type": ItemType.TILE,
		"atlas": Vector2i(0, 0),
		"icon": "", # 运行时由 TileSet 图集裁剪填充
		"description": "基础地表泥土砖块，用于铺设地面或垫高阶梯。"
	},

	# --- 武器装备 (WEAPON) ---
	{
		"id": "stick_wand",
		"name": "木棍法杖",
		"category": Category.WEAPON,
		"type": ItemType.WEAPON,
		"icon": "res://resources/object/weapon/stick/stick.png",
		"weapon_tex": "res://resources/object/weapon/stick/stick.png",
		"description": "初级手持法杖，左键发射魔法弹，右键发射照明弹。",
		"aim_config": {
			"laser_length": 180.0,
			"laser_color": Color(1.0, 0.95, 0.2, 0.85),
			"projectile_speed": 520.0,
			"drop_value": 800.0,
			"launch_height": 10.0,
			"trajectory_color": Color(0.4, 0.8, 1.0, 0.85)
		}
	},
	{
		"id": "long_bow",
		"name": "远射长弓",
		"category": Category.WEAPON,
		"type": ItemType.WEAPON,
		"icon": "res://resources/object/weapon/stick/stick.png",
		"weapon_tex": "res://resources/object/weapon/stick/stick.png",
		"description": "超远射程长弓，弹道平直，下坠极小，视野范围扩大。",
		"aim_config": {
			"radius_min": 40.0,
			"radius_horizontal": 280.0,
			"radius_max": 420.0,
			"laser_length": 280.0,
			"ring_color": Color(0.3, 0.8, 1.0, 0.75),
			"laser_color": Color(0.4, 0.9, 1.0, 0.9),
			"projectile_speed": 680.0,
			"drop_value": 360.0,
			"launch_height": 10.0,
			"trajectory_color": Color(0.5, 0.9, 1.0, 0.9)
		}
	},

	# --- 杂项物品 (OBJECT) ---
	{
		"id": "dirt_block",
		"name": "泥土块",
		"category": Category.OBJECT,
		"type": ItemType.OBJECT,
		"scene": "res://scene/object/dirt.tscn",
		"icon": "res://resources/object/dirt.png",
		"grid_size": Vector2i(1, 1),
		"description": "挖掘泥土砖后掉落的泥土块道具。"
	},
]

# 按分类获取物品列表
static func get_items_by_category(category: Category) -> Array[Dictionary]:
	if category == Category.ALL:
		return ITEMS.duplicate()
	var result: Array[Dictionary] = []
	for item in ITEMS:
		if item.get("category") == category:
			result.append(item)
	return result

# 按 ID 查找物品
static func get_item_by_id(item_id: String) -> Dictionary:
	for item in ITEMS:
		if item.get("id") == item_id:
			return item
	return {}

