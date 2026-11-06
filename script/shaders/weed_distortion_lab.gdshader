shader_type canvas_item;
render_mode blend_mix;

// ==============================================================================
// 杂草 Photoshop 自由变换与弧形弯曲重采样 Shader
// (Photoshop-Style Free Transform & Curved Warp Resampling Shader)
// ==============================================================================

group_uniforms Photoshop_Transform;
// 顶边拉长/缩短比例 (Top Width Scale)：1.0 为原始 4px，2.0 为拉宽至 8px，0.5 为收窄至 2px
uniform float top_width_scale : hint_range(0.1, 3.5, 0.05) = 1.0;
// 高度压缩/拉伸比例 (Height Scale)：1.0 为原始 8px，0.5 为压扁至 4px，1.2 为拉伸至 9.6px
uniform float height_scale : hint_range(0.15, 1.8, 0.05) = 1.0;
// 水平侧倾倾斜量 (Horizontal Shear)：草尖横向偏倒像素位移 (单位为纹素像素)
uniform float horizontal_shear : hint_range(-12.0, 12.0, 0.1) = 0.0;
// 基底旋转角度 (Base Rotation Angle)：绕底部中心 (0, 0) 旋转整个贴图 (度，如 45° 模拟极强横风刚体倾倒)
uniform float base_rotation_deg : hint_range(-60.0, 60.0, 1.0) = 0.0;
// 弯曲柔韧指数 (Bend Exponent)：1.0 为直斜切，1.8 为自然抛物线弯曲，3.0 为尖端剧烈折叠
uniform float bend_exponent : hint_range(0.8, 3.5, 0.05) = 1.8;
// 重采样模式：true 为双线性平滑插值 (像 PS 缩放插值)，false 为邻近硬像素重采样 (经典像素画)
uniform bool resample_bilinear = true;

group_uniforms Display_Mode;
// 是否为无形变的原图幽灵参考层 (半透明白/灰色)
uniform bool is_ghost = false;
// 幽灵层透明度
uniform float ghost_alpha : hint_range(0.0, 1.0, 0.05) = 0.35;
// 草体赋色 (对应地表三阶色)
uniform vec4 tuft_color : source_color = vec4(0.396, 0.596, 0.078, 1.0);
// 草尖高光微增
uniform float tip_brightness : hint_range(0.0, 0.3, 0.01) = 0.08;

group_uniforms Live_Wind_Simulation;
// 是否开启动态狂风起伏摆动测试
uniform bool live_wind_mode = false;
// 模拟风力强度 (最大侧向推倒位移)
uniform float sim_wind_strength : hint_range(1.0, 15.0, 0.2) = 6.0;
// 模拟纵向迎面/背向风比重 (-1.0 顶风收细顶边，+1.0 顺风拉宽顶边)
uniform float sim_wind_dir_y : hint_range(-1.0, 1.0, 0.05) = 0.3;
// 模拟风速频率
uniform float sim_wind_speed : hint_range(0.5, 8.0, 0.1) = 2.5;

varying vec2 local_pos;

void vertex() {
	if (!is_ghost) {
		// 对称均匀扩展四边形外边界，为大幅度侧倾、顶边拉伸与 45° 旋转留出充裕画布空间
		VERTEX.x *= 6.0;
		if (UV.y > 0.5) {
			VERTEX.y += 8.0;
		} else {
			VERTEX.y *= 2.5;
		}
	}
	// local_pos 即为四边形内每个片段相对于草根锚点 (0, 0) 的真实局部像素坐标
	local_pos = VERTEX;
}

void fragment() {
	if (is_ghost) {
		// 幽灵层：直接绘制未变形的原图
		vec4 tex = texture(TEXTURE, UV);
		if (tex.a < 0.1) {
			discard;
		}
		COLOR = vec4(1.0, 1.0, 1.0, ghost_alpha * tex.a);
	} else {
		// 计算当前形变参数 (静态手动或动态狂风)
	float eff_top_scale = top_width_scale;
	float eff_height_scale = height_scale;
	float eff_shear = horizontal_shear;
	float eff_rot = base_rotation_deg;

	if (live_wind_mode) {
		// 动态连续阵风波形
		float w1 = sin(TIME * sim_wind_speed);
		float w2 = sin(TIME * sim_wind_speed * 2.17) * 0.35;
		float gust = w1 + w2; // -1.35 ~ +1.35

		eff_shear = gust * sim_wind_strength;
		eff_rot += gust * (sim_wind_strength * 3.5);
		// 强风吹倒时顺带高度下压 (狂风贴地)
		float squash_amt = abs(gust) * (sim_wind_strength * 0.06);
		eff_height_scale = clamp(1.0 - squash_amt, 0.25, 1.2);
		// 纵向风向导致的近大远小顶边拉长/收缩
		eff_top_scale = clamp(1.0 + (sim_wind_dir_y * abs(gust) * 0.6), 0.3, 2.5);
	}

	// 绕草根 (0, 0) 逆旋转局部采样坐标
	float rot_rad = radians(eff_rot);
	float cos_r = cos(rot_rad);
	float sin_r = sin(rot_rad);
	vec2 p = vec2(local_pos.x * cos_r + local_pos.y * sin_r, -local_pos.x * sin_r + local_pos.y * cos_r);

	// p.y = 0 是小草根部接地线，向上为负 Y (0 到 -8)
	float y_up = -p.y;
	float cur_total_h = 8.0 * eff_height_scale;

	// 垂直范围超出小草当前高度直接剔除
	if (y_up < 0.0 || y_up > cur_total_h) {
		discard;
	}

	// 归一化高度比例：h = 0.0 (草根) ~ 1.0 (草尖)
	float h = clamp(y_up / cur_total_h, 0.0, 1.0);

	// 1. 中轴线弧形弯曲与水平侧倾 (Photoshop 弯曲曲线)
	float center_x = eff_shear * pow(h, bend_exponent);

	// 2. 顶边梯形拉伸/收窄：当前高度截面下的实际宽度 (Photoshop 自由变换透视拉伸)
	float cur_w = 4.0 * mix(1.0, eff_top_scale, h);

	// 3. 相对中轴线的横向距离
	float rel_x = p.x - center_x;

	// 4. 重采样纹理坐标 (U, V)
	float u = (rel_x / cur_w) + 0.5;
	float v = 1.0 - h;

	// 横向超出小草当前宽度直接剔除
	if (u < 0.0 || u > 1.0) {
		discard;
	}

	// 5. 纹理重采样 (支持双线性平滑抗锯齿插值 或 经典像素邻近重采样)
	vec4 tex = vec4(0.0);
	if (resample_bilinear) {
		tex = texture(TEXTURE, vec2(u, v));
	} else {
		// 邻近硬重采样
		vec2 tex_size = vec2(textureSize(TEXTURE, 0));
		vec2 snapped_uv = (floor(vec2(u, v) * tex_size) + 0.5) / tex_size;
		tex = texture(TEXTURE, snapped_uv);
	}

	if (tex.a < 0.1) {
		discard;
	}

	// 6. 草皮基础三阶赋色与草尖高光
	vec3 final_color = tuft_color.rgb;
	if (tip_brightness > 0.0) {
		final_color += vec3(tip_brightness * (1.0 - v));
	}

	COLOR = vec4(final_color, tex.a * COLOR.a);
	}
}
