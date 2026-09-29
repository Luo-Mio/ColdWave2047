shader_type canvas_item;
render_mode unshaded;

// trajectory_occlusion.gdshader —— GPU 弹道/地面射线遮挡着色器
// 利用全局高度场纹理在片元级别实时判定遮挡，彻底消除 CPU 端的 while 步进与二分查找

// ====== 高度场纹理采样参数 (与 GridData 常量对齐) ======
uniform sampler2D height_map_tex : filter_nearest, repeat_disable;
uniform vec2 height_map_origin = vec2(-128.0, -128.0);   // GridData.HEIGHT_MAP_OFFSET 取负
uniform vec2 height_map_size   = vec2(256.0, 256.0);     // GridData.HEIGHT_MAP_WIDTH/HEIGHT
uniform float max_floor_val    = 16.0;                    // R8 编码: floor / max_floor_val
uniform float floor_height     = 16.0;                    // 每层高度 (像素)

// ====== 视觉参数 (由 GDScript 每帧动态注入) ======
uniform vec4 visual_color : source_color      = vec4(0.4, 0.8, 1.0, 0.85);  // 主弹道/地面射线颜色
uniform float occluded_alpha_ratio             = 0.5;                         // 遮挡处透明度倍率

// 渐变模式 (悬崖延长弹道)
uniform vec4 gradient_start_color : source_color = vec4(1.0, 0.88, 0.25, 0.9);
uniform vec4 gradient_end_color   : source_color = vec4(1.0, 0.22, 0.22, 0.95);

// 地面射线模式 (启用楼层截断)
uniform bool is_ground_ray        = false;
uniform float player_floor        = 0.0;
uniform bool require_same_floor   = false;

// Z 值编码范围 (顶点颜色 R 通道 = point_z / encode_max_z)
uniform float encode_max_z = 256.0;

varying vec2 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// ====== 等距坐标转换 (移植自 terrain_raymarch.gdshader, 与 GridData.world_to_cell 像素级对齐) ======
vec2 world_to_cell(vec2 pos) {
	float cy_base = floor(pos.y / 16.0) - 1.0;

	vec2 best_cell = vec2(0.0);
	float min_dist = 999999.0;

	for (int dy = -1; dy <= 1; dy++) {
		float cy = cy_base + float(dy);
		float mod_val = mod(cy, 2.0);
		if (mod_val < 0.0) {
			mod_val += 2.0;
		}
		float shift = (mod_val > 0.5 && mod_val < 1.5) ? 32.0 : 0.0;
		float cx = floor((pos.x - 32.0 - shift) / 64.0 + 0.5);
		vec2 center = vec2(32.0 + cx * 64.0 + shift, (cy + 1.0) * 16.0);
		float d = abs(pos.x - center.x) / 32.0 + abs(pos.y - center.y) / 16.0;
		if (d < min_dist) {
			min_dist = d;
			best_cell = vec2(cx, cy);
		}
	}
	return best_cell;
}

// 从高度场纹理采样指定网格格子的最高楼层
float get_cell_floor(vec2 cell) {
	vec2 tex_coord = (cell - height_map_origin + vec2(0.5)) / height_map_size;
	if (tex_coord.x < 0.0 || tex_coord.x > 1.0 || tex_coord.y < 0.0 || tex_coord.y > 1.0) {
		return 0.0;
	}
	return texture(height_map_tex, tex_coord).r * max_floor_val;
}

// ====== GPU 遮挡判定 (替代 CPU is_point_occluded 循环) ======
// 从最高层向下按 8px 步进检查：屏幕上该位置是否有高于 point_z 的地砖挡住了视线
bool is_occluded(vec2 screen_pt, float point_z) {
	float max_h = max_floor_val * floor_height;
	if (point_z >= max_h) {
		return false;
	}
	for (float z = max_h; z > point_z + 0.5; z -= 8.0) {
		vec2 test_ground = vec2(screen_pt.x, screen_pt.y + z);
		vec2 cell = world_to_cell(test_ground);
		float h_floor = get_cell_floor(cell) * floor_height;
		if (h_floor >= z) {
			return true;
		}
	}
	return false;
}

void fragment() {
	// 1. 从顶点颜色解码数据
	//    R = 归一化 z 值 (point_z / encode_max_z)
	//    G = 渐变进度 (0 = 非渐变, 0.001~1.0 = 悬崖渐变)
	//    B = 未使用
	//    A = 未使用
	float point_z    = COLOR.r * encode_max_z;
	float gradient_t = COLOR.g;

	// 2. 地面射线模式：楼层截断判定
	if (is_ground_ray) {
		float pf_z = player_floor * floor_height;
		vec2 ground_pos = vec2(v_world_pos.x, v_world_pos.y + pf_z);
		vec2 cell = world_to_cell(ground_pos);
		float cell_fl = get_cell_floor(cell);

		if (require_same_floor) {
			if (abs(cell_fl - player_floor) > 0.5) discard;
		} else {
			if (cell_fl > player_floor + 0.5) discard;
		}
	}

	// 3. 确定视觉颜色
	vec4 base_color;
	if (gradient_t > 0.001) {
		base_color = mix(gradient_start_color, gradient_end_color, gradient_t);
	} else {
		base_color = visual_color;
	}

	// 4. GPU 遮挡检测
	bool occ = is_occluded(v_world_pos, point_z);
	float alpha = occ ? base_color.a * occluded_alpha_ratio : base_color.a;

	COLOR = vec4(base_color.rgb, alpha);
}

