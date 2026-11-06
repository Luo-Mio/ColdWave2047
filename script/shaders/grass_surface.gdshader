shader_type canvas_item;
render_mode blend_mix;

group_uniforms Debug_Preview;
// 调试阅览模式:
// 0: 正常游戏渲染 (地表原貌上色)
// 1: 原始地表噪波灰度预览 (查看世界空间黑白底噪)
// 2: 阈值斑块二值遮罩 (清晰查看斑块边界线)
// 3: 预览第一层风波灰度 (Wave 1: 黑=-1, 白=+1，直观查看主风带走向与波峰间距)
// 4: 预览第二层风波灰度 (Wave 2: 黑=-1, 白=+1，直观查看侧向干扰风带)
// 5: 预览混合阵风黑白波带 (Wave 1 * Wave 2: 黑=无风/反向, 白=强阵风峰值)
// 6: 预览混合阵风彩色热力带 (蓝=静风区, 绿/黄=微风, 橙红=强阵风带，全图宏观俯瞰风带宽度与流速)
uniform int debug_mode : hint_enum("0: 正常游戏地表", "1: 地表噪波灰度", "2: 斑块阈值遮罩", "3: 预览第一层风波 (Wave 1)", "4: 预览第二层风波 (Wave 2)", "5: 预览混合阵风黑白波带", "6: 预览混合阵风彩色热力带") = 0;

group_uniforms Wind_Sync;
// 第一层独立风力噪波贴图 (可在 resources/surface/wind/wind_noise_1.tres 中独立自由编辑)
uniform sampler2D wind_noise_1 : repeat_enable, filter_linear;
// 第二层独立风力噪波贴图 (可在 resources/surface/wind/wind_noise_2.tres 中独立自由编辑)
uniform sampler2D wind_noise_2 : repeat_enable, filter_linear;

// 风场主速度：控制风波在整张地图上行进掠过的快慢节奏 (需与 tuft 材质保持一致)
uniform float wind_speed : hint_range(0.0, 10.0, 0.1) = 2.0;
// 风场主导方向向量
uniform vec2 wind_base_dir = vec2(1.0, 0.3);
// 风力噪波空间尺度 (控制阵风团块大小，数值越小阵风团块越大，类似草皮色斑 scale)
uniform float wind_noise_scale : hint_range(0.0005, 0.02, 0.0005) = 0.002;
// 两个噪波层的分叉夹角 (弧度，约 23 度，产生流体交错互扰感，打破单向平移)
uniform float noise_diverge_angle : hint_range(0.0, 1.57, 0.02) = 0.40;
// 阵风平衡阈值 (让平静时居中在 0，阵风波峰重叠时爆发强风)
uniform float wind_noise_threshold : hint_range(-0.5, 0.5, 0.02) = 0.25;

group_uniforms Noise_Sampling;
// 噪波纹理 (NoiseTexture2D + FastNoiseLite)
uniform sampler2D noise_tex : repeat_enable, filter_linear;
// 世界空间缩放与偏移 (默认 Y 为 X 的 2 倍，校正 2:1 等距菱形投影，保证噪波斑块呈现自然的圆形而非扁椭圆)
uniform vec2 noise_scale = vec2(0.003, 0.006);
uniform vec2 noise_offset = vec2(0.0, 0.0);

group_uniforms Color_Thresholds;
// 单阈值切换：当 threshold_dark <= 0.0 时生效为单阈值模式 (即参考项目的经典算法)
uniform float threshold_bright : hint_range(0.0, 1.0, 0.005) = 0.58; // 亮色斑块阈值 (高于此值变为亮斑)
uniform float threshold_dark : hint_range(0.0, 1.0, 0.005) = 0.40;   // 暗色斑块阈值 (低于此值变为暗斑，设为 0 则关闭暗斑)
uniform float softness : hint_range(0.0, 0.2, 0.005) = 0.0;          // 边缘柔和度 (设为 0 即为纯像素硬切色块)

group_uniforms Pixel_Snap;
uniform bool snap_to_pixel_grid = true;                        // 是否将噪波色斑吸附到游戏像素网格
uniform float pixel_size : hint_range(1.0, 8.0, 1.0) = 1.0;    // 像素块大小 (1.0 代表 1:1 游戏原生像素纹素)

group_uniforms Colors;
uniform vec4 color_light : source_color = vec4(0.365, 0.522, 0.082, 1.0); // 浅绿 #5d8515
uniform vec4 color_mid : source_color = vec4(0.306, 0.486, 0.078, 1.0);   // 中绿 #4e7c14
uniform vec4 color_dark : source_color = vec4(0.255, 0.467, 0.000, 1.0);  // 深绿 #417700

varying vec2 world_pos;

// 向量旋转辅助函数 (用于双层噪波分叉流向)
vec2 rotate_vec2(vec2 v, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

// 彩色热力图渐变映射 (从无风深海蓝到微风青绿，再到中风明黄与强风炽红)
vec3 heat_map(float v) {
	vec3 c1 = vec3(0.05, 0.10, 0.35); // 静风无力 (深海蓝)
	vec3 c2 = vec3(0.10, 0.75, 0.85); // 微风拂动 (青蓝)
	vec3 c3 = vec3(0.90, 0.85, 0.15); // 中度风力 (明黄)
	vec3 c4 = vec3(1.00, 0.20, 0.05); // 强阵风峰值 (炽红)
	if (v < 0.33) {
		return mix(c1, c2, v / 0.33);
	} else if (v < 0.66) {
		return mix(c2, c3, (v - 0.33) / 0.33);
	} else {
		return mix(c3, c4, (v - 0.66) / 0.34);
	}
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a < 0.01) {
		discard;
	}

	// 像素化对齐：将世界坐标吸附到整像素网格中心
	vec2 base_pos = world_pos;
	if (snap_to_pixel_grid) {
		base_pos = (floor(world_pos / pixel_size) + 0.5) * pixel_size;
	}

	// 检查器缩略图预览适配：若 world_pos 接近原点 (检查器虚拟四边形)，则使用 UV 展开完整视窗
	bool is_inspector_preview = (abs(world_pos.x) < 0.01 && abs(world_pos.y) < 0.01);
	vec2 iso_world = is_inspector_preview ? (UV * 1000.0) : vec2(base_pos.x * 0.8, base_pos.y * 1.8);
	vec2 sample_uv = (iso_world + noise_offset) * noise_scale;

	float n = texture(noise_tex, sample_uv).r;

	vec3 grass_color = color_mid.rgb;
	float bright_factor = 0.0;
	float dark_factor = 0.0;

	if (threshold_dark > 0.0) {
		// 三段式：深绿 < 中绿 < 浅绿
		if (softness <= 0.001) {
			bright_factor = step(threshold_bright, n);
			dark_factor = step(n, threshold_dark);
			if (bright_factor > 0.5) {
				grass_color = color_light.rgb;
			} else if (dark_factor > 0.5) {
				grass_color = color_dark.rgb;
			}
		} else {
			bright_factor = smoothstep(threshold_bright - softness, threshold_bright + softness, n);
			dark_factor = smoothstep(threshold_dark + softness, threshold_dark - softness, n);
			grass_color = mix(grass_color, color_light.rgb, bright_factor);
			grass_color = mix(grass_color, color_dark.rgb, dark_factor);
		}
	} else {
		// 单阈值二段式
		bright_factor = (softness <= 0.001) ? step(threshold_bright, n) : smoothstep(threshold_bright - softness, threshold_bright + softness, n);
		grass_color = mix(color_mid.rgb, color_light.rgb, bright_factor);
	}

	// 调试模式分支输出
	if (debug_mode == 1) {
		// 1. 原始地表噪波黑白灰度图
		COLOR = vec4(vec3(n), tex.a * COLOR.a);
	} else if (debug_mode == 2) {
		// 2. 斑块阈值遮罩
		COLOR = vec4(vec3(bright_factor), tex.a * COLOR.a);
	} else if (debug_mode >= 3 && debug_mode <= 6) {
		// 双层草皮同源噪波分叉漂移与相乘调制 (像草皮色斑一样的天然气流团块)
		vec2 dir_norm = normalize(wind_base_dir);
		vec2 dir1 = rotate_vec2(dir_norm, noise_diverge_angle);
		vec2 dir2 = rotate_vec2(dir_norm, -noise_diverge_angle);

		vec2 drift1 = dir1 * (TIME * wind_speed * 0.05);
		vec2 drift2 = dir2 * (TIME * (wind_speed * 0.89) * 0.05);

		vec2 uv1 = (iso_world + noise_offset) * wind_noise_scale - drift1;
		vec2 uv2 = (iso_world + noise_offset) * (wind_noise_scale * 0.85) - drift2;

		float s1 = texture(wind_noise_1, uv1).r;
		float s2 = texture(wind_noise_2, uv2).r;

		float gust = s1 * s2;
		gust = clamp(gust + wind_noise_threshold, 0.0, 1.0);
		gust = (gust - 0.5) * 2.0;

		if (debug_mode == 3) {
			// 3. 预览第一层风噪波 (直接查看与草皮色斑同源的有机团块)
			COLOR = vec4(vec3(s1), tex.a * COLOR.a);
		} else if (debug_mode == 4) {
			// 4. 预览第二层风噪波 (斜向漂移有机团块)
			COLOR = vec4(vec3(s2), tex.a * COLOR.a);
		} else if (debug_mode == 5) {
			// 5. 预览混合阵风黑白波块 (两层相乘后的独立阵风气流团)
			COLOR = vec4(vec3(gust * 0.5 + 0.5), tex.a * COLOR.a);
		} else if (debug_mode == 6) {
			// 6. 预览混合阵风彩色热力带 (蓝=静风区, 绿/黄=微风, 橙红=强阵风团块)
			COLOR = vec4(heat_map(gust * 0.5 + 0.5), tex.a * COLOR.a);
		}
	} else {
		// 0. 正常模式：纯遮罩 + 纯噪波上色 (tex.a 决定几何形状与边缘剪影，grass_color 赋色)
		COLOR = vec4(grass_color, tex.a * COLOR.a);
	}
}

