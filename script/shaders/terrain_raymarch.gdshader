shader_type canvas_item;

// 2.5D 高度场 3D 视线步进阴影 Shader
// 运行于 fog_viewport 的底层背景，为全屏渲染真实的地形遮挡阴影

uniform sampler2D height_map_tex : filter_nearest, repeat_disable;
uniform vec2 height_map_origin = vec2(-128.0, -128.0);
uniform vec2 height_map_size = vec2(256.0, 256.0);
uniform float max_floor_val = 16.0;
uniform float floor_height = 16.0;
uniform float layer_offset_y = -16.0;

uniform vec2 player_ground_pos;
uniform float player_eye_z;
uniform int raymarch_steps = 32;
uniform int max_search_floor = 6;
uniform float shadow_softness = 8.0;

varying vec2 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// 世界坐标映射到 Godot STACKED 等轴测网格坐标 (与 Godot TileMapLayer local_to_map 100% 像素级对齐)
vec2 world_to_cell(vec2 pos) {
	vec2 loc = pos - vec2(0.0, layer_offset_y);
	float cy_base = floor(loc.y / 16.0) - 1.0;
	
	vec2 best_cell = vec2(0.0);
	float min_dist = 999999.0;
	
	for (int dy = -1; dy <= 1; dy++) {
		float cy = cy_base + float(dy);
		float mod_val = mod(cy, 2.0);
		if (mod_val < 0.0) {
			mod_val += 2.0;
		}
		float shift = (mod_val > 0.5 && mod_val < 1.5) ? 32.0 : 0.0;
		float cx = floor((loc.x - 32.0 - shift) / 64.0 + 0.5);
		vec2 center = vec2(32.0 + cx * 64.0 + shift, (cy + 1.0) * 16.0);
		float d = abs(loc.x - center.x) / 32.0 + abs(loc.y - center.y) / 16.0;
		if (d < min_dist) {
			min_dist = d;
			best_cell = vec2(cx, cy);
		}
	}
	return best_cell;
}

// 查询网格上的最高楼层数值
float get_cell_floor(vec2 cell) {
	vec2 tex_coord = (cell - height_map_origin + vec2(0.5)) / height_map_size;
	if (tex_coord.x < 0.0 || tex_coord.x > 1.0 || tex_coord.y < 0.0 || tex_coord.y > 1.0) {
		return 0.0;
	}
	return texture(height_map_tex, tex_coord).r * max_floor_val;
}

// 根据屏幕像素反推出其展示的 3D 地表坐标 (Ground X, Ground Y, Surface Z)
vec3 find_surface_3d(vec2 vpos) {
	for (int f = 6; f >= 1; f--) {
		if (f > max_search_floor) {
			continue;
		}
		vec2 ground_pos = vec2(vpos.x, vpos.y + float(f) * floor_height);
		vec2 cell = world_to_cell(ground_pos);
		float h_floor = get_cell_floor(cell);
		if (h_floor >= float(f)) {
			return vec3(ground_pos, float(f) * floor_height);
		}
	}
	return vec3(vpos, 0.0);
}

// 经典的交错梯度噪声 (Interleaved Gradient Noise)，将固定步长阶梯完全随机抖散
float interleaved_gradient_noise(vec2 screen_pos) {
	return fract(52.9829189 * fract(dot(screen_pos, vec2(0.06711056, 0.00583715))));
}

// 3D 视线遮挡与软阴影判定
float compute_visibility(vec3 eye, vec3 target, int steps, vec2 frag_coord) {
	// 如果受光顶面高于（或等于）视线高度，则该水平顶面背面朝向角色，物理上不可见
	if (target.z >= eye.z) {
		return 0.0;
	}

	vec3 diff = target - eye;
	float dist_sq = dot(diff.xy, diff.xy);
	// 目标与眼睛过近（例如角色脚底），直接判定为可见
	if (dist_sq < 16.0) {
		return 1.0;
	}

	vec2 player_cell = world_to_cell(eye.xy);
	float jitter = interleaved_gradient_noise(frag_coord);
	float min_vis = 1.0;

	for (int i = 1; i < 64; i++) {
		if (i >= steps - 1) {
			break;
		}
		// 结合抖动的连续步进
		float s = clamp((float(i) + jitter - 0.5) / float(steps), 0.0, 1.0);
		vec2 cur_pos_2d = mix(eye.xy, target.xy, s);
		float cur_ray_z = mix(eye.z, target.z, s);
		vec2 cell = world_to_cell(cur_pos_2d);

		// 角色自身所站网格不作为遮挡物
		if (cell == player_cell) {
			continue;
		}

		float h = get_cell_floor(cell) * floor_height;
		
		// 关键过滤：地形高度处于目标受光面（或更低）时，属于地表基底本身，绝不可作为遮挡物
		if (h <= target.z + 0.1) {
			continue;
		}
		
		float clearance = cur_ray_z - h;
		if (clearance < -0.5) {
			return 0.0; // 完全处于遮挡之下
		}
		if (shadow_softness > 0.001) {
			float t = clamp((clearance + 0.5) / shadow_softness, 0.0, 1.0);
			float soft = smoothstep(0.0, 1.0, t); // S 型缓动平滑过渡，浓度渐变极柔和
			min_vis = min(min_vis, soft);
		}
	}
	return min_vis;
}

void fragment() {
	vec3 surface = find_surface_3d(v_world_pos);
	vec3 eye = vec3(player_ground_pos, player_eye_z);
	
	float vis = compute_visibility(eye, surface, raymarch_steps, FRAGCOORD.xy);
	COLOR = vec4(vis, 0.0, 0.0, 1.0);
}
