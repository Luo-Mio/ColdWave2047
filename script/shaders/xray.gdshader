// xray.gdshader —— 2D 等距物体高耸遮挡透视 Shader (平滑不透明度渐变)
shader_type canvas_item;

// 全局玩家透视参数 (全部由角色 MainChara 属性在检查器中直接控制)
global uniform vec2 player_world_pos;
global uniform vec2 xray_radius;
global uniform float xray_max_transparency;
global uniform float xray_feather;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 col = COLOR;
	if (col.a <= 0.001) {
		discard;
	}

	// 1. 计算当前片元与玩家世界坐标的归一化 2:1 等轴测椭圆距离
	vec2 r = max(xray_radius, vec2(1.0, 1.0));
	vec2 diff = world_pos - player_world_pos;
	float dist = length(diff / r);

	// 2. 当片元落在玩家透视光晕范围内时，直接平滑渐变降低不透明度（无颗粒点阵）
	if (dist < 1.0) {
		float feather_val = clamp(xray_feather, 0.01, 1.0);
		// smoothstep 计算从外边缘 (dist=1.0, strength=0) 到中心 (dist=1.0-feather_val, strength=1.0) 的平滑过渡
		float strength = smoothstep(1.0, 1.0 - feather_val, dist) * xray_max_transparency;
		col.a *= (1.0 - strength);
	}

	COLOR = col;
}
