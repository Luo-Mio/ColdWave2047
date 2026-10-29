// xray.gdshader —— 2D 等距物体高耸遮挡透视 Shader (支持 8x8 64阶平滑抖动与交织噪波)
shader_type canvas_item;

// 全局玩家透视参数 (全部由角色 MainChara 属性在检查器中直接控制！)
global uniform vec2 player_world_pos;
global uniform vec2 xray_radius;
global uniform float xray_max_transparency;
global uniform float xray_feather;
global uniform int xray_dither_scale;
global uniform int xray_dither_mode; // 0 = Bayer 8x8 (64阶平滑), 1 = Interleaved Noise (无级噪波), 2 = Bayer 4x4 (16阶粗颗粒)

// 4x4 经典 Bayer 像素抖动矩阵 (16 阶灰度)
const mat4 bayer4 = mat4(
	vec4( 0.0/16.0, 12.0/16.0,  3.0/16.0, 15.0/16.0),
	vec4( 8.0/16.0,  4.0/16.0, 11.0/16.0,  7.0/16.0),
	vec4( 2.0/16.0, 14.0/16.0,  1.0/16.0, 13.0/16.0),
	vec4(10.0/16.0,  6.0/16.0,  9.0/16.0,  5.0/16.0)
);

// 8x8 经典 Bayer 像素抖动矩阵 (64 阶高精度灰度，彻底消除分层断层)
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

	// 2. 当片元落在玩家透视光晕范围内时，执行像素点阵抖动镂空
	if (dist < 1.0) {
		float feather_val = clamp(xray_feather, 0.01, 1.0);
		float strength = smoothstep(1.0, 1.0 - feather_val, dist) * xray_max_transparency;

		int scale = max(xray_dither_scale, 1);
		vec2 coord = floor(FRAGCOORD.xy / float(scale));
		float threshold = 0.5;

		if (xray_dither_mode == 0) {
			// 8x8 Bayer 矩阵 (64 阶超平滑色阶，彻底消除 16 阶的分层断层)
			int px = int(coord.x) % 8;
			if (px < 0) px += 8;
			int py = int(coord.y) % 8;
			if (py < 0) py += 8;
			threshold = bayer8[py * 8 + px];
		} else if (xray_dither_mode == 1) {
			// Interleaved Gradient Noise (连续无级微噪波，极致柔和自然)
			threshold = fract(52.9829189 * fract(dot(coord, vec2(0.06711056, 0.00583715))));
		} else {
			// 4x4 Bayer 矩阵 (经典 16 阶粗颗粒)
			int px = int(coord.x) % 4;
			if (px < 0) px += 4;
			int py = int(coord.y) % 4;
			if (py < 0) py += 4;
			threshold = bayer4[px][py];
		}

		if (strength > threshold) {
			discard;
		}
	}

	COLOR = col;
}
