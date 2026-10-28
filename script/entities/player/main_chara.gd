# main_chara.gd —— 玩家主角实体控制器 (组件调度中枢)
class_name MainChara
extends CharacterBody2D

@onready var input_comp: PlayerInputComponent = $PlayerInputComponent
@onready var mover_comp: MoverComponent = $MoverComponent
@onready var anim_comp: FourDirAnimComponent = $FourDirAnimComponent
@onready var inventory_comp: InventoryComponent = $InventoryComponent

func _physics_process(delta: float) -> void:
	# 1. 从输入大脑获取 8 向输入向量
	var move_dir := input_comp.get_movement_direction() if input_comp else Vector2.ZERO
	
	# 2. 交给移动驱动组件执行 2:1 等距物理滑动
	var current_velocity := mover_comp.move(move_dir, delta) if mover_comp else Vector2.ZERO
	
	# 3. 交给动画组件更新四向帧动画
	if anim_comp:
		anim_comp.update_animation(current_velocity)

