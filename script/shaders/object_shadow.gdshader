shader_type canvas_item;

// 物体动态阴影 Shader (用于实体立柱如 Trunk 树干，仅接收阴影，绝不透视镂空)
uniform float shadow_darkness : hint_range(0.0, 1.0) = 0.35;
uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform bool enable_dither_fog = true;
uniform int dither_scale : hint_range(1, 4) = 1;

// 每个物体独立控制是否处于阴影中 (支持 instance uniform 零冗余动态控制)
instance uniform bool is_in_shadow = false;

// 8x8 经典 Bayer 像素抖动矩阵 (用于阴影投影叠加)
const float bayer8[64] = float[64](
    0.000000, 0.500000, 0.125000, 0.625000, 0.031250, 0.531250, 0.156250, 0.656250,
    0.750000, 0.250000, 0.875000, 0.375000, 0.781250, 0.281250, 0.906250, 0.406250,
    0.187500, 0.687500, 0.062500, 0.562500, 0.218750, 0.718750, 0.093750, 0.593750,
    0.937500, 0.437500, 0.812500, 0.312500, 0.968750, 0.468750, 0.843750, 0.343750,
    0.046875, 0.546875, 0.171875, 0.671875, 0.015625, 0.515625, 0.140625, 0.640625,
    0.796875, 0.296875, 0.921875, 0.421875, 0.765625, 0.265625, 0.890625, 0.390625,
    0.234375, 0.734375, 0.109375, 0.609375, 0.203125, 0.703125, 0.078125, 0.578125,
    0.984375, 0.484375, 0.859375, 0.359375, 0.953125, 0.453125, 0.828125, 0.328125
);

void fragment() {
    vec4 col = COLOR;
    if (col.a <= 0.001) { discard; }

    // 动态阴影叠加：仅当物体处于阴影内时叠加阴影，不在阴影内时保持 100% 原色 (地表阴影在物体之下)
    if (is_in_shadow) {
        if (enable_dither_fog) {
            int px = (int(FRAGCOORD.x) / dither_scale) % 8;
            if (px < 0) px += 8;
            int py = (int(FRAGCOORD.y) / dither_scale) % 8;
            if (py < 0) py += 8;
            float threshold = bayer8[py * 8 + px];

            if (shadow_darkness > threshold) {
                col = vec4(shadow_color.rgb, col.a);
            }
        } else {
            col = vec4(mix(col.rgb, shadow_color.rgb, shadow_darkness), col.a);
        }
    }

    COLOR = col;
}
