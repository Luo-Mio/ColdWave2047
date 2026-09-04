shader_type canvas_item;

global uniform vec2 player_world_pos;

// 透视中心相对于角色脚底坐标的世界偏移量 (例如 (0, -24) 可将透视中心上移至角色面部/胸部)
uniform vec2 target_offset = vec2(0.0, 0.0);

uniform float rx : hint_range(4.0, 400.0) = 85.0;
uniform float ry : hint_range(4.0, 400.0) = 55.0;
uniform float feather : hint_range(0.01, 1.0) = 0.8;
uniform float max_transparency : hint_range(0.0, 1.0) = 0.85; // 0.0=完全实心, 1.0=中心完全镂空透明


// 4x4 经典 Bayer 像素抖动矩阵
const mat4 bayer = mat4(
    vec4( 0.0/16.0, 12.0/16.0,  3.0/16.0, 15.0/16.0),
    vec4( 8.0/16.0,  4.0/16.0, 11.0/16.0,  7.0/16.0),
    vec4( 2.0/16.0, 14.0/16.0,  1.0/16.0, 13.0/16.0),
    vec4(10.0/16.0,  6.0/16.0,  9.0/16.0,  5.0/16.0)
);

varying vec2 v_world_pos;

void vertex() {
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
    vec4 col = texture(TEXTURE, UV);
    if (col.a <= 0.001) { discard; }

    // 1. 近身椭圆透视 (针对角色走到树木近处/面部)
    vec2 target_pos = player_world_pos + target_offset;
    vec2 diff = (v_world_pos - target_pos) / vec2(rx, ry);
    float dist_sq = dot(diff, diff);
    float proximity_mask = 0.0;
    if (dist_sq < 1.0) {
        proximity_mask = (1.0 - smoothstep(1.0 - feather, 1.0, dist_sq)) * max_transparency;
    }

    // 角色为中心范围内的近身椭圆透视 (针对角色走到树木/物体近处或被遮挡)
    float final_mask = proximity_mask;

    if (final_mask > 0.0) {
        // 像素点阵抖动：利用屏幕绝对像素对齐镂空
        int x = int(FRAGCOORD.x) % 4;
        int y = int(FRAGCOORD.y) % 4;
        float dither_threshold = bayer[x][y];

        // 越靠近中心或视线照射越充分，被剔除的像素越多
        if (final_mask > dither_threshold) {
            discard;
        }
    }

    COLOR = col;
}