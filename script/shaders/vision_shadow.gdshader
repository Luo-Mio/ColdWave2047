// vision_shadow.gdshader —— 视线盲区多边形像素噪点着色器 (径向极角透视对齐 + 边缘柔和虚化)
shader_type canvas_item;

varying vec2 local_pos;

uniform vec2 player_pos = vec2(0.0, 0.0);
uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float shadow_darkness : hint_range(0.0, 1.0) = 0.65;
uniform float edge_softness : hint_range(0.0, 0.5) = 0.10;
uniform int dither_scale : hint_range(1, 4) = 1;
uniform int dither_mode : hint_range(0, 2) = 0; // 0 = Bayer 8x8 (64阶平滑), 1 = Interleaved Noise (无级噪波), 2 = Bayer 4x4 (16阶经典)

// 4x4 经典 Bayer 像素抖动矩阵
const mat4 bayer4 = mat4(
	vec4( 0.0/16.0, 12.0/16.0,  3.0/16.0, 15.0/16.0),
	vec4( 8.0/16.0,  4.0/16.0, 11.0/16.0,  7.0/16.0),
	vec4( 2.0/16.0, 14.0/16.0,  1.0/16.0, 13.0/16.0),
	vec4(10.0/16.0,  6.0/16.0,  9.0/16.0,  5.0/16.0)
);

// 8x8 经典 Bayer 像素抖动矩阵 (64 阶超平滑色阶)
const float bayer8[64] = float[64](
	 0.0/64.0, 32.0/64.0,  8.0/64.0, 40.0/64.0,  2.0/64.0, 34.0/64.0, 10.0/64.0, 42.0/64.0,
	48.0/64.0, 16.0/64.0, 56.0/64.0, 24.0/64.0, 50.0/64.0, 18.0/64.0, 58.0/64.0, 26.0/64.0,
	12.0/64.0, 44.0/64.0,  4.0/64.0, 36.0/64.0, 14.0/64.0, 46.0/64.0,  6.0/64.0, 38.0/64.0,
	60.0/64.0, 28.0/64.0, 52.0/64.0, 20.0/64.0, 62.0/64.0, 30.0/64.0, 54.0/64.0, 22.0/64.0,
	 3.0/64.0, 35.0/64.0, 11.0/64.0, 43.0/64.0,  1.0/64.0, 33.0/64.0,  9.0/64.0, 41.0/64.0,
	51.0/64.0, 19.0/64.0, 59.0/64.0, 27.0/64.0, 49.0/64.0, 17.0/64.0, 57.0/64.0, 25.0/64.0,
	15.0/64.0, 47.0/64.0,  7.0/64.0, 39.0/64.0, 13.0/64.0, 45.0/64.0,  5.0/64.0, 37.0/64.0,
	63.0/64.0, 31.0/64.0, 55.0/64.0, 23.0/64.0, 61.0/64.0, 29.0/64.0, 53.0/64.0, 21.0/64.0
);

void vertex() {
	// 在顶点着色阶段准确捕获片元本地坐标
	local_pos = VERTEX;
}

void fragment() {
	// 1. 基于视线发射源的真实径向极角计算 (基于本地坐标插值，无对角线畸变)
	float theta_left = UV.x;
	float span = max(UV.y, 0.0001);

	vec2 diff = local_pos - player_pos;
	float frag_ang = atan(diff.y, diff.x);

	float rel = mod(frag_ang - theta_left + PI, TAU) - PI;

	float u = clamp(rel / span, 0.0, 1.0);
	float edge_dist = min(u, 1.0 - u);

	float edge_factor = 1.0;
	if (edge_softness > 0.001) {
		float t = clamp(edge_dist / edge_softness, 0.0, 1.0);
		edge_factor = smoothstep(0.0, 1.0, t);
	}

	float effective_darkness = shadow_darkness * edge_factor;
	if (effective_darkness <= 0.001) {
		discard;
	}

	// 2. 屏幕空间像素抖动阈值计算
	int scale = max(dither_scale, 1);
	vec2 coord = floor(FRAGCOORD.xy / float(scale));
	float threshold = 0.5;

	if (dither_mode == 0) {
		int px = int(coord.x) % 8;
		if (px < 0) px += 8;
		int py = int(coord.y) % 8;
		if (py < 0) py += 8;
		threshold = bayer8[py * 8 + px];
	} else if (dither_mode == 1) {
		threshold = fract(52.9829189 * fract(dot(coord, vec2(0.06711056, 0.00583715))));
	} else {
		int px = int(coord.x) % 4;
		if (px < 0) px += 4;
		int py = int(coord.y) % 4;
		if (py < 0) py += 4;
		threshold = bayer4[px][py];
	}

	if (effective_darkness > threshold) {
		COLOR = shadow_color;
	} else {
		discard;
	}
}
