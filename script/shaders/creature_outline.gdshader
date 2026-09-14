shader_type canvas_item;

// creature_outline.gdshader —— 生物受瞄准高亮绿色像素描边着色器
// 使用 instance uniform 实现所有生物共享单材质对象，零额外渲染批次开销

instance uniform bool is_targeted = false;
instance uniform vec4 outline_color : source_color = vec4(0.2, 1.0, 0.4, 1.0);
instance uniform float outline_width = 1.0;

void fragment() {
	// Godot 的 COLOR 进入片元着色器时已包含贴图与 modulate，直接使用避免二次乘算导致变黑
	vec4 col = COLOR;

	if (is_targeted && col.a <= 0.01) {
		vec2 size = TEXTURE_PIXEL_SIZE * outline_width;
		float max_a = 0.0;

		// 8 方向邻域采样 (十字正方向 + 4个对角线)，形成饱满平滑的像素硬质描边
		max_a = max(max_a, texture(TEXTURE, UV + vec2(size.x, 0.0)).a);
		max_a = max(max_a, texture(TEXTURE, UV - vec2(size.x, 0.0)).a);
		max_a = max(max_a, texture(TEXTURE, UV + vec2(0.0, size.y)).a);
		max_a = max(max_a, texture(TEXTURE, UV - vec2(0.0, size.y)).a);

		max_a = max(max_a, texture(TEXTURE, UV + vec2(size.x, size.y)).a);
		max_a = max(max_a, texture(TEXTURE, UV + vec2(-size.x, size.y)).a);
		max_a = max(max_a, texture(TEXTURE, UV + vec2(size.x, -size.y)).a);
		max_a = max(max_a, texture(TEXTURE, UV + vec2(-size.x, -size.y)).a);

		if (max_a > 0.01) {
			col = outline_color;
		}
	}

	COLOR = col;
}
