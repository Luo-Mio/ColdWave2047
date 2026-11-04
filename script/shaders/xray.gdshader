// xray.gdshader —— 2D 等距物体高耸遮挡透视 Shader (整株树木平滑半透明淡出，基于物体向上高度胶囊体区间判定)
shader_type canvas_item;

// 全局玩家透视参数 (全部由角色 MainChara 属性在检查器中直接控制)
global uniform vec2 player_world_pos; // 玩家世界坐标 (XY，脚底中心)
global uniform bool xray_y_sort_filter; // 是否启用 Y-Sort 遮挡深度过滤 (仅当物体在角色前方遮挡时才淡出)
global uniform vec2 xray_radius; // 判定半径 (X: 水平半宽例如 55.0, Y: 顶部/底部羽化半高例如 25.0)
global uniform float xray_max_transparency; // 最大透光度 (例如 0.70 => 透视后剩余 0.30 不透明度)
global uniform float xray_feather; // 边缘淡入淡出羽化区间 (例如 0.40)

// 遮挡物向上延伸的高度 (像素，胶囊体向上覆盖的区间，可通过 set_instance_shader_parameter 动态自动获取，默认 115.0)
instance uniform float object_height = 115.0;

varying vec2 obj_world_pos;

void vertex() {
	// 提取当前物体在地面根部的世界坐标 (0, 0)
	obj_world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 col = COLOR;
	if (col.a <= 0.001) {
		discard;
	}

	// 角色相对物体地面根部的垂直高度差 (角色在树身后/往上为负数，在树身前/往下为正数)
	float rel_y = player_world_pos.y - obj_world_pos.y;

	// 垂直中轴胶囊体投影钳位：从地面根部 (0.0) 到树冠顶部 (-object_height)
	// 角色向上离开树冠时 (-object_height 向上) 具有平滑距离渐变；
	// 角色向下离开树根时 (0.0 向下) 采用完全相同的胶囊体距离渐变，极简且统一
	float clamped_y = clamp(rel_y, -object_height, 0.0);

	// 计算到垂直胶囊中轴线的最短距离向量 (横向 delta.x, 纵向超出部分 delta.y)
	vec2 r = max(xray_radius, vec2(1.0, 1.0));
	vec2 delta = vec2(player_world_pos.x - obj_world_pos.x, rel_y - clamped_y);
	float dist = length(delta / r);

	if (dist < 1.0) {
		float feather_val = clamp(xray_feather, 0.01, 1.0);
		float factor = smoothstep(1.0, 1.0 - feather_val, dist) * xray_max_transparency;
		col.a *= (1.0 - factor);
	}

	COLOR = col;
}
