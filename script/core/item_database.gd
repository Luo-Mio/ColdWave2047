# item_database.gd —— 全局物品注册表与数据库 (Autoload)
extends Node

enum ItemType {
	NONE = 0,
	TILE = 1,    # 地砖 (如: 泥土)
	SURF = 2,    # 覆盖层 (如: 草皮)
	OBJECT = 3,  # 放置物 (如: 树木、作物、箱子)
	WEAPON = 4   # 武器工具 (如: 剑、斧、木棍)
}

# 注册所有游戏物品的核心字典
var _items: Dictionary = {
	"birch_tree": {
		"id": "birch_tree",
		"name": "白桦树",
		"type": ItemType.OBJECT,
		"category": "nature",
		"icon": "res://resources/object/Tree/BirchTree/BirchTree002.png",
		"scene": "res://scene/Object/Tree/BritchTree/britch_tree.tscn",
		"grid_size": Vector2i(4, 4),
		"max_stack": 99,
		"description": "挺拔优雅的白桦树。\n占地: 4x4 (整格)\n拥有树叶遮挡透视与投影效果。"
	},
	"autumn_tree": {
		"id": "autumn_tree",
		"name": "秋季橡树",
		"type": ItemType.OBJECT,
		"category": "nature",
		"icon": "res://resources/object/Tree/OakTree/AutumnTree.png",
		"scene": "res://scene/Object/Tree/OakTree/autumn_tree.tscn",
		"grid_size": Vector2i(4, 4),
		"max_stack": 99,
		"description": "金黄秋色的橡树。\n占地: 4x4 (整格)\n拥有树叶遮挡透视与投影效果。"
	},
	"wheat": {
		"id": "wheat",
		"name": "小麦",
		"type": ItemType.OBJECT,
		"category": "nature",
		"icon": "res://resources/object/Plant/wheat/wheat.png",
		"scene": "res://scene/Object/Plant/wheat.tscn",
		"grid_size": Vector2i(1, 1),
		"max_stack": 99,
		"description": "金黄的小麦作物。\n占地: 1x1 (微格)\n可密集精细种植。"
	},
	"dirt_tile": {
		"id": "dirt_tile",
		"name": "泥土地块",
		"type": ItemType.TILE,
		"category": "terrain",
		"icon": "res://resources/tiles/base_dirt_tile/base_dirt_tile.png",
		"atlas": Vector2i(0, 0),
		"grid_size": Vector2i(4, 4),
		"max_stack": 99,
		"description": "基础泥土地块。\n铺设后自动扩展地面与空气墙。"
	},
	"grass_surf": {
		"id": "grass_surf",
		"name": "青草地表",
		"type": ItemType.SURF,
		"category": "terrain",
		"icon": "res://resources/surface/GreenGrass/grass_icon.png",
		"atlas": Vector2i(0, 0),
		"grid_size": Vector2i(4, 4),
		"max_stack": 99,
		"description": "翠绿的青草地表覆盖物。"
	}
}

## 获取单个物品的完整定义 (深拷贝，防止外部误改数据库)
func get_item(id: String) -> Dictionary:
	if _items.has(id):
		return _items[id].duplicate(true)
	return {}

## 创建物品实例数据 (附带数量，count = -1 表示无限)
func create_item(id: String, count: int = 1) -> Dictionary:
	var item := get_item(id)
	if not item.is_empty():
		item["count"] = count
	return item

## 获取所有已注册物品列表
func get_all_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for k in _items:
		result.append(_items[k].duplicate(true))
	return result

## 按分类筛选物品列表 ("all", "nature", "terrain" 等)
func get_items_by_category(category: String) -> Array[Dictionary]:
	if category == "all" or category.is_empty():
		return get_all_items()
	var result: Array[Dictionary] = []
	for k in _items:
		if _items[k].get("category", "") == category:
			result.append(_items[k].duplicate(true))
	return result

## 动态注册新物品 (方便日后模组或扩展)
func register_item(id: String, data: Dictionary) -> void:
	data["id"] = id
	_items[id] = data

