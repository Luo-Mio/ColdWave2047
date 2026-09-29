shader_type canvas_item;
render_mode unshaded;

// impact_grid_falloff.gdshader —— GPU 着弹点网格椭圆径向衰减着色器
// 替代 CPU 逐顶点椭圆距离计算, 在片元级别实时生成平滑二次衰减

// ====== 衰减参数 (由 GDScript 每帧动态注入) ======
uniform vec2 hit_world_pos  = vec2(0.0, 0.0);   // 着弹点世界坐标
uniform float radius_x      = 128.0;              // 椭圆水平半径 (像素)
uniform float radius_y      = 64.0;               // 椭圆垂直半径 (像素)

varying vec2 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 delta = (v_world_pos - hit_world_pos) / vec2(radius_x, radius_y);
	float d_sq = dot(delta, delta);

	// 椭圆范围外直接丢弃 (零渲染开销)
	if (d_sq >= 1.0) {
		discard;
	}

	// 平滑二次衰减: 中心 100% 强度, 边缘 0% 丝滑隐形
	float falloff = 1.0 - d_sq;
	COLOR.a *= falloff;
}

